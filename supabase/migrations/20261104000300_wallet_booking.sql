-- Wallet, booking and cancellation.
--
-- Errors: every rejection raises P0001 with a stable machine code as the message
-- and JSON parameters in DETAIL. The app turns these into Arabic sentences.
--
-- Lock order, used everywhere to avoid deadlocks:
--   wallet(s), sorted by employee_id -> offering(s), sorted by id -> booking

create function private.fail(p_code text, p_details jsonb default '{}')
returns void
language plpgsql
as $$
begin
  raise exception '%', p_code using errcode = 'P0001', detail = p_details::text;
end;
$$;

create function private.require_role(variadic p_roles public.user_role[])
returns uuid
language plpgsql
stable
as $$
begin
  if private.app_role() is null or not private.app_role() = any (p_roles) then
    perform private.fail('forbidden');
  end if;
  return auth.uid();
end;
$$;

-- Returns the stored response if this key already completed, null if the caller
-- should do the work. A concurrent duplicate waits here on the primary key until
-- the first transaction ends; if that one rolled back, the duplicate proceeds.
create function private.idem_begin(p_operation text, p_key uuid)
returns jsonb
language plpgsql
as $$
declare
  v_response jsonb;
begin
  if p_key is null then
    perform private.fail('missing_idempotency_key');
  end if;

  insert into private.idempotency_keys (actor_id, operation, key)
  values (auth.uid(), p_operation, p_key)
  on conflict do nothing;

  if found then
    return null;
  end if;

  select response into v_response
  from private.idempotency_keys
  where actor_id = auth.uid() and operation = p_operation and key = p_key;

  return v_response;
end;
$$;

create function private.idem_finish(p_operation text, p_key uuid, p_response jsonb)
returns jsonb
language plpgsql
as $$
begin
  update private.idempotency_keys
  set response = p_response
  where actor_id = auth.uid() and operation = p_operation and key = p_key;
  return p_response;
end;
$$;

create function private.audit(p_action text, p_entity text, p_entity_id text, p_details jsonb default '{}')
returns void
language sql
as $$
  insert into public.audit_log (actor_id, action, entity, entity_id, details)
  values (auth.uid(), p_action, p_entity, p_entity_id, p_details);
$$;

create function private.notify(p_user_id uuid, p_type text, p_payload jsonb default '{}')
returns void
language sql
as $$
  insert into public.notifications (user_id, type, payload)
  values (p_user_id, p_type, p_payload);
$$;

-- The only place wallet balances change. Balance and ledger move together.
create function private.post_tx(
  p_employee_id uuid,
  p_type public.wallet_tx_type,
  p_available_delta bigint,
  p_held_delta bigint,
  p_booking_id uuid default null,
  p_note text default null
)
returns void
language plpgsql
as $$
begin
  update public.wallets
  set available = available + p_available_delta,
      held = held + p_held_delta,
      updated_at = now()
  where employee_id = p_employee_id;

  if not found then
    perform private.fail('wallet_not_found', jsonb_build_object('employee_id', p_employee_id));
  end if;

  insert into public.wallet_transactions (employee_id, type, available_delta, held_delta, booking_id, note, created_by)
  values (p_employee_id, p_type, p_available_delta, p_held_delta, p_booking_id, p_note, auth.uid());
end;
$$;

create function private.lock_wallet(p_employee_id uuid)
returns public.wallets
language plpgsql
as $$
declare
  v_wallet public.wallets;
begin
  select * into v_wallet from public.wallets where employee_id = p_employee_id for update;
  if not found then
    perform private.fail('wallet_not_found', jsonb_build_object('employee_id', p_employee_id));
  end if;
  return v_wallet;
end;
$$;

-- Issues a token for one holder of one booking. If the holder already has a live
-- token, keeps it and only re-points it when the new delegation should own it.
create function private.issue_token(
  p_booking_id uuid,
  p_holder_id uuid,
  p_restaurant_id uuid,
  p_delegation_id uuid default null,
  p_take_over boolean default false
)
returns void
language plpgsql
as $$
declare
  v_attempt integer := 0;
  v_code text;
begin
  if exists (
    select 1 from public.pickup_tokens
    where booking_id = p_booking_id and holder_id = p_holder_id and revoked_at is null
  ) then
    if p_take_over then
      update public.pickup_tokens
      set delegation_id = p_delegation_id
      where booking_id = p_booking_id and holder_id = p_holder_id and revoked_at is null;
    end if;
    return;
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := lpad((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text, 6, '0');
    begin
      insert into public.pickup_tokens (booking_id, holder_id, restaurant_id, delegation_id, token, short_code)
      values (p_booking_id, p_holder_id, p_restaurant_id, p_delegation_id,
              encode(extensions.gen_random_bytes(16), 'hex'), v_code);
      return;
    exception when unique_violation then
      -- A short code collided with another live token at this restaurant.
      if v_attempt >= 10 then
        raise;
      end if;
    end;
  end loop;
end;
$$;

create function private.revoke_booking_tokens(p_booking_id uuid)
returns void
language sql
as $$
  update public.pickup_tokens
  set revoked_at = now()
  where booking_id = p_booking_id and revoked_at is null;
$$;

-- ---------------------------------------------------------------------------
-- Employee: book and cancel
-- ---------------------------------------------------------------------------

-- All or nothing: any rejected offering means no booking and no deduction.
create function public.book_meals(p_offering_ids uuid[], p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_employee_id uuid := private.require_role('employee');
  v_restaurant_id uuid := private.my_restaurant_id();
  v_previous jsonb;
  v_wallet public.wallets;
  v_ids uuid[];
  v_offering public.meal_offerings;
  v_total bigint := 0;
  v_booking_id uuid;
  v_booking_ids uuid[] := '{}';
  v_standing record;
  v_context jsonb;
begin
  v_previous := private.idem_begin('book_meals', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  select array_agg(distinct id order by id) into v_ids from unnest(p_offering_ids) as id;
  if v_ids is null then
    perform private.fail('empty_selection');
  end if;

  v_wallet := private.lock_wallet(v_employee_id);

  select d.id, d.delegate_id into v_standing
  from public.delegations d
  join public.profiles p on p.id = d.delegate_id and p.is_active
  where d.delegator_id = v_employee_id and d.scope = 'standing' and d.revoked_at is null;

  for v_offering in
    select * from public.meal_offerings where id = any (v_ids) order by id for update
  loop
    v_context := jsonb_build_object(
      'offering_id', v_offering.id,
      'service_date', v_offering.service_date,
      'period', v_offering.period
    );

    if v_offering.restaurant_id <> v_restaurant_id then
      perform private.fail('wrong_restaurant', v_context);
    end if;
    if v_offering.status <> 'open' then
      perform private.fail('offering_cancelled', v_context);
    end if;
    if now() >= v_offering.book_until then
      perform private.fail('booking_closed', v_context || jsonb_build_object('book_until', v_offering.book_until));
    end if;
    if v_offering.capacity is not null and v_offering.booked_count >= v_offering.capacity then
      perform private.fail('sold_out', v_context);
    end if;
    if exists (
      select 1 from public.bookings
      where employee_id = v_employee_id and offering_id = v_offering.id
        and status not in ('cancelled', 'cancelled_by_restaurant')
    ) then
      perform private.fail('already_booked', v_context);
    end if;

    v_total := v_total + v_offering.price;
  end loop;

  if (select count(*) from public.meal_offerings where id = any (v_ids)) <> cardinality(v_ids) then
    perform private.fail('offering_not_found');
  end if;

  if v_wallet.available < v_total then
    perform private.fail('insufficient_balance', jsonb_build_object(
      'total', v_total,
      'available', v_wallet.available,
      'shortfall', v_total - v_wallet.available
    ));
  end if;

  for v_offering in
    select * from public.meal_offerings where id = any (v_ids) order by id
  loop
    insert into public.bookings (employee_id, offering_id, restaurant_id, amount)
    values (v_employee_id, v_offering.id, v_offering.restaurant_id, v_offering.price)
    returning id into v_booking_id;

    update public.meal_offerings set booked_count = booked_count + 1 where id = v_offering.id;

    perform private.post_tx(v_employee_id, 'hold', -v_offering.price, v_offering.price, v_booking_id);
    perform private.issue_token(v_booking_id, v_employee_id, v_offering.restaurant_id);

    if v_standing.id is not null then
      perform private.issue_token(v_booking_id, v_standing.delegate_id, v_offering.restaurant_id, v_standing.id);
    end if;

    v_booking_ids := v_booking_ids || v_booking_id;
  end loop;

  return private.idem_finish('book_meals', p_key, jsonb_build_object(
    'booking_ids', to_jsonb(v_booking_ids),
    'total', v_total,
    'available', v_wallet.available - v_total,
    'held', v_wallet.held + v_total
  ));
end;
$$;

create function public.cancel_booking(p_booking_id uuid, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_employee_id uuid := private.require_role('employee');
  v_previous jsonb;
  v_wallet public.wallets;
  v_offering public.meal_offerings;
  v_booking public.bookings;
begin
  v_previous := private.idem_begin('cancel_booking', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  v_wallet := private.lock_wallet(v_employee_id);

  select * into v_offering
  from public.meal_offerings
  where id = (select offering_id from public.bookings where id = p_booking_id and employee_id = v_employee_id)
  for update;

  if not found then
    perform private.fail('booking_not_found');
  end if;

  -- Filtered by owner: a delegate holding a token cannot cancel someone's booking.
  select * into v_booking
  from public.bookings
  where id = p_booking_id and employee_id = v_employee_id
  for update;

  if v_booking.status <> 'booked' then
    perform private.fail('not_cancellable', jsonb_build_object('status', v_booking.status));
  end if;
  if now() >= v_offering.cancel_until then
    perform private.fail('cancel_deadline_passed', jsonb_build_object('cancel_until', v_offering.cancel_until));
  end if;

  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_booking.id;
  update public.meal_offerings set booked_count = booked_count - 1 where id = v_offering.id;
  perform private.post_tx(v_employee_id, 'release', v_booking.amount, -v_booking.amount, v_booking.id);
  perform private.revoke_booking_tokens(v_booking.id);

  return private.idem_finish('cancel_booking', p_key, jsonb_build_object(
    'refunded', v_booking.amount,
    'available', v_wallet.available + v_booking.amount,
    'held', v_wallet.held - v_booking.amount
  ));
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: credit and corrections
-- ---------------------------------------------------------------------------

create function public.admin_top_up(p_employee_ids uuid[], p_amount bigint, p_note text, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_previous jsonb;
  v_ids uuid[];
  v_id uuid;
  v_count integer := 0;
begin
  perform private.require_role('admin');

  v_previous := private.idem_begin('admin_top_up', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  if p_amount is null or p_amount <= 0 then
    perform private.fail('invalid_amount');
  end if;

  select array_agg(distinct id order by id) into v_ids from unnest(p_employee_ids) as id;
  if v_ids is null then
    perform private.fail('empty_selection');
  end if;

  foreach v_id in array v_ids loop
    if not exists (
      select 1 from public.profiles where id = v_id and role = 'employee' and is_active
    ) then
      perform private.fail('invalid_employee', jsonb_build_object('employee_id', v_id));
    end if;

    perform private.lock_wallet(v_id);
    perform private.post_tx(v_id, 'topup', p_amount, 0, null, p_note);
    perform private.notify(v_id, 'balance_added', jsonb_build_object('amount', p_amount));
    v_count := v_count + 1;
  end loop;

  perform private.audit('top_up', 'wallet', null, jsonb_build_object(
    'employee_ids', to_jsonb(v_ids), 'amount', p_amount, 'note', p_note
  ));

  return private.idem_finish('admin_top_up', p_key, jsonb_build_object(
    'employees', v_count,
    'total', v_count * p_amount
  ));
end;
$$;

-- A correction is a new ledger line with a written reason; history is never edited.
create function public.admin_adjust(p_employee_id uuid, p_amount bigint, p_reason text, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_previous jsonb;
  v_wallet public.wallets;
begin
  perform private.require_role('admin');

  v_previous := private.idem_begin('admin_adjust', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  if p_amount is null or p_amount = 0 then
    perform private.fail('invalid_amount');
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    perform private.fail('reason_required');
  end if;

  v_wallet := private.lock_wallet(p_employee_id);

  if v_wallet.available + p_amount < 0 then
    perform private.fail('insufficient_balance', jsonb_build_object(
      'available', v_wallet.available,
      'shortfall', -(v_wallet.available + p_amount)
    ));
  end if;

  perform private.post_tx(p_employee_id, 'adjustment', p_amount, 0, null, p_reason);
  perform private.audit('adjust', 'wallet', p_employee_id::text, jsonb_build_object('amount', p_amount, 'reason', p_reason));

  return private.idem_finish('admin_adjust', p_key, jsonb_build_object(
    'available', v_wallet.available + p_amount,
    'held', v_wallet.held
  ));
end;
$$;

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.app_role() to authenticated;
grant execute on function private.my_restaurant_id() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.manages(uuid) to authenticated;
grant execute on function private.offset_minutes(integer, time) to authenticated;

revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.book_meals(uuid[], uuid) to authenticated;
grant execute on function public.cancel_booking(uuid, uuid) to authenticated;
grant execute on function public.admin_top_up(uuid[], bigint, text, uuid) to authenticated;
grant execute on function public.admin_adjust(uuid, bigint, text, uuid) to authenticated;
