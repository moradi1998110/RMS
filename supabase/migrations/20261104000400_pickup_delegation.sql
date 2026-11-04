-- Pickup redemption, delegation and no-show settlement.
-- A scan rejection is a normal outcome, returned as {ok: false, reason} so the
-- scanner can show it; only permission problems raise.

create function private.redeem(
  p_token public.pickup_tokens,
  p_scanner_id uuid,
  p_method public.pickup_method
)
returns jsonb
language plpgsql
as $$
declare
  v_owner_id uuid;
  v_booking public.bookings;
  v_offering public.meal_offerings;
  v_owner_name text;
  v_holder_name text;
  v_meal_name text;
begin
  if p_token.restaurant_id <> private.my_restaurant_id() then
    return jsonb_build_object('ok', false, 'reason', 'wrong_restaurant');
  end if;

  select employee_id into v_owner_id from public.bookings where id = p_token.booking_id;
  perform private.lock_wallet(v_owner_id);

  -- Two simultaneous scans of the owner's and delegate's tokens serialize here,
  -- and the second one sees picked_up.
  select * into v_booking from public.bookings where id = p_token.booking_id for update;
  select * into v_offering from public.meal_offerings where id = v_booking.offering_id;

  if v_booking.status = 'picked_up' then
    return jsonb_build_object(
      'ok', false,
      'reason', 'already_picked_up',
      'picked_up_at', v_booking.picked_up_at,
      'picked_up_by_name', (select full_name from public.profiles where id = v_booking.picked_up_by)
    );
  end if;
  if v_booking.status in ('cancelled', 'cancelled_by_restaurant') then
    return jsonb_build_object('ok', false, 'reason', 'cancelled');
  end if;
  if v_booking.status = 'no_show' then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;
  -- Re-read under the wallet lock: a delegation may have been revoked since the
  -- caller fetched this token.
  if (select revoked_at from public.pickup_tokens where id = p_token.id) is not null
     or not exists (select 1 from public.profiles where id = p_token.holder_id and is_active) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_token');
  end if;
  if now() < v_offering.pickup_from then
    return jsonb_build_object('ok', false, 'reason', 'not_started', 'pickup_from', v_offering.pickup_from);
  end if;
  if now() >= v_offering.pickup_until then
    return jsonb_build_object('ok', false, 'reason', 'expired', 'pickup_until', v_offering.pickup_until);
  end if;

  update public.bookings
  set status = 'picked_up',
      picked_up_at = now(),
      picked_up_by = p_token.holder_id,
      scanned_by = p_scanner_id,
      pickup_method = p_method,
      settled_at = now()
  where id = v_booking.id;

  perform private.post_tx(v_owner_id, 'settle_pickup', 0, -v_booking.amount, v_booking.id);
  perform private.revoke_booking_tokens(v_booking.id);

  select full_name into v_owner_name from public.profiles where id = v_owner_id;
  select full_name into v_holder_name from public.profiles where id = p_token.holder_id;
  select name into v_meal_name from public.meals where id = v_offering.meal_id;

  return jsonb_build_object(
    'ok', true,
    'booking_id', v_booking.id,
    'owner_name', v_owner_name,
    'holder_name', v_holder_name,
    'meal_name', v_meal_name,
    'period', v_offering.period
  );
end;
$$;

create function public.redeem_pickup(p_token text, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_manager_id uuid := private.require_role('manager');
  v_previous jsonb;
  v_token public.pickup_tokens;
begin
  v_previous := private.idem_begin('redeem_pickup', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  select * into v_token from public.pickup_tokens where token = p_token;
  if not found then
    return private.idem_finish('redeem_pickup', p_key, jsonb_build_object('ok', false, 'reason', 'invalid_token'));
  end if;

  return private.idem_finish('redeem_pickup', p_key, private.redeem(v_token, v_manager_id, 'scan'));
end;
$$;

-- Fallback when a code cannot be scanned. Only live tokens at the manager's own
-- restaurant match, so a short code is unambiguous.
create function public.redeem_short_code(p_code text, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_manager_id uuid := private.require_role('manager');
  v_previous jsonb;
  v_token public.pickup_tokens;
begin
  v_previous := private.idem_begin('redeem_short_code', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  select * into v_token
  from public.pickup_tokens
  where short_code = p_code
    and restaurant_id = private.my_restaurant_id()
    and revoked_at is null;

  if not found then
    return private.idem_finish('redeem_short_code', p_key, jsonb_build_object('ok', false, 'reason', 'invalid_token'));
  end if;

  return private.idem_finish('redeem_short_code', p_key, private.redeem(v_token, v_manager_id, 'short_code'));
end;
$$;

-- For deliveries made by hand during an internet outage, recorded afterwards.
-- A booking already settled as no_show only changes status, since both outcomes
-- deduct the same amount.
create function public.record_manual_delivery(p_booking_id uuid, p_reason text, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_manager_id uuid := private.require_role('manager');
  v_previous jsonb;
  v_owner_id uuid;
  v_booking public.bookings;
  v_offering public.meal_offerings;
  v_previous_status public.booking_status;
begin
  v_previous := private.idem_begin('record_manual_delivery', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    perform private.fail('reason_required');
  end if;

  select employee_id into v_owner_id
  from public.bookings
  where id = p_booking_id and restaurant_id = private.my_restaurant_id();

  if not found then
    perform private.fail('booking_not_found');
  end if;

  perform private.lock_wallet(v_owner_id);
  select * into v_booking from public.bookings where id = p_booking_id for update;
  select * into v_offering from public.meal_offerings where id = v_booking.offering_id;
  v_previous_status := v_booking.status;

  if v_booking.status not in ('booked', 'no_show') then
    perform private.fail('not_deliverable', jsonb_build_object('status', v_booking.status));
  end if;
  if now() < v_offering.pickup_from or now() >= v_offering.pickup_until + interval '3 days' then
    perform private.fail('outside_manual_window');
  end if;

  update public.bookings
  set status = 'picked_up',
      picked_up_at = now(),
      picked_up_by = v_owner_id,
      scanned_by = v_manager_id,
      pickup_method = 'manual',
      settled_at = coalesce(settled_at, now())
  where id = v_booking.id;

  if v_previous_status = 'booked' then
    perform private.post_tx(v_owner_id, 'settle_pickup', 0, -v_booking.amount, v_booking.id, p_reason);
  end if;

  perform private.revoke_booking_tokens(v_booking.id);
  perform private.audit('manual_delivery', 'booking', v_booking.id::text, jsonb_build_object(
    'reason', p_reason, 'previous_status', v_previous_status
  ));

  return private.idem_finish('record_manual_delivery', p_key, jsonb_build_object('ok', true, 'booking_id', v_booking.id));
end;
$$;

-- Everything the current user can collect right now or soon: their own meals and
-- those delegated to them. The app caches this so codes show on a weak connection.
create function public.my_pickups()
returns table (
  booking_id uuid,
  token text,
  short_code text,
  is_mine boolean,
  owner_name text,
  meal_name text,
  period public.meal_period,
  service_date date,
  pickup_from timestamptz,
  pickup_until timestamptz
)
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select
    b.id,
    t.token,
    t.short_code,
    b.employee_id = auth.uid(),
    p.full_name,
    m.name,
    o.period,
    o.service_date,
    o.pickup_from,
    o.pickup_until
  from public.pickup_tokens t
  join public.bookings b on b.id = t.booking_id
  join public.meal_offerings o on o.id = b.offering_id
  join public.meals m on m.id = o.meal_id
  join public.profiles p on p.id = b.employee_id
  where t.holder_id = auth.uid()
    and private.app_role() = 'employee'
    and t.revoked_at is null
    and b.status = 'booked'
    and o.status = 'open'
    and o.pickup_until > now()
  order by o.pickup_from, b.employee_id = auth.uid() desc, p.full_name;
$$;

-- ---------------------------------------------------------------------------
-- Delegation
-- ---------------------------------------------------------------------------

-- Exact match only, same restaurant only, and rate limited, so usernames cannot
-- be used to browse staff.
create function public.find_colleague(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_employee_id uuid := private.require_role('employee');
  v_result jsonb;
begin
  delete from private.colleague_lookups
  where user_id = v_employee_id and created_at < now() - interval '10 minutes';

  if (select count(*) from private.colleague_lookups where user_id = v_employee_id) >= 10 then
    perform private.fail('too_many_attempts');
  end if;

  insert into private.colleague_lookups (user_id) values (v_employee_id);

  select jsonb_build_object('username', username, 'full_name', full_name, 'department', department)
  into v_result
  from public.profiles
  where username = lower(btrim(p_username))
    and role = 'employee'
    and is_active
    and restaurant_id = private.my_restaurant_id()
    and id <> v_employee_id;

  return v_result;
end;
$$;

-- Revokes one delegation and the live tokens that exist because of it.
create function private.end_delegation(p_delegation_id uuid)
returns void
language plpgsql
as $$
begin
  update public.delegations
  set revoked_at = now()
  where id = p_delegation_id and revoked_at is null;

  update public.pickup_tokens
  set revoked_at = now()
  where delegation_id = p_delegation_id and revoked_at is null;
end;
$$;

-- p_booking_id set: this meal only. Null: all my meals until I revoke.
-- Only the booking's owner can delegate, so a delegate cannot pass it further.
create function public.set_delegation(p_delegate_username text, p_booking_id uuid, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_employee_id uuid := private.require_role('employee');
  v_previous jsonb;
  v_delegate public.profiles;
  v_delegation_id uuid;
  v_old_id uuid;
  v_booking record;
begin
  v_previous := private.idem_begin('set_delegation', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  select * into v_delegate
  from public.profiles
  where username = lower(btrim(p_delegate_username))
    and role = 'employee'
    and is_active
    and restaurant_id = private.my_restaurant_id();

  if not found then
    perform private.fail('colleague_not_found');
  end if;
  if v_delegate.id = v_employee_id then
    perform private.fail('cannot_delegate_to_self');
  end if;

  -- Serializes with book_meals, which reads the standing delegation under this lock.
  perform private.lock_wallet(v_employee_id);

  if p_booking_id is null then
    select id into v_old_id
    from public.delegations
    where delegator_id = v_employee_id and scope = 'standing' and revoked_at is null;

    if v_old_id is not null then
      perform private.end_delegation(v_old_id);
    end if;

    insert into public.delegations (delegator_id, delegate_id, scope)
    values (v_employee_id, v_delegate.id, 'standing')
    returning id into v_delegation_id;

    for v_booking in
      select b.id, b.restaurant_id
      from public.bookings b
      join public.meal_offerings o on o.id = b.offering_id
      where b.employee_id = v_employee_id and b.status = 'booked' and o.pickup_until > now()
      order by b.id
    loop
      perform private.issue_token(v_booking.id, v_delegate.id, v_booking.restaurant_id, v_delegation_id);
    end loop;
  else
    select b.id, b.restaurant_id into v_booking
    from public.bookings b
    join public.meal_offerings o on o.id = b.offering_id
    where b.id = p_booking_id
      and b.employee_id = v_employee_id
      and b.status = 'booked'
      and o.pickup_until > now()
    for update of b;

    if not found then
      perform private.fail('booking_not_delegable');
    end if;

    select id into v_old_id
    from public.delegations
    where booking_id = p_booking_id and scope = 'booking' and revoked_at is null;

    if v_old_id is not null then
      perform private.end_delegation(v_old_id);
    end if;

    insert into public.delegations (delegator_id, delegate_id, scope, booking_id)
    values (v_employee_id, v_delegate.id, 'booking', p_booking_id)
    returning id into v_delegation_id;

    perform private.issue_token(p_booking_id, v_delegate.id, v_booking.restaurant_id, v_delegation_id, true);
  end if;

  perform private.notify(v_delegate.id, 'delegation_received', jsonb_build_object(
    'delegation_id', v_delegation_id,
    'from_name', (select full_name from public.profiles where id = v_employee_id),
    'booking_id', p_booking_id
  ));

  return private.idem_finish('set_delegation', p_key, jsonb_build_object(
    'delegation_id', v_delegation_id,
    'delegate_name', v_delegate.full_name
  ));
end;
$$;

-- Safe to repeat: revoking an already revoked delegation changes nothing.
create function public.revoke_delegation(p_delegation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_employee_id uuid := private.require_role('employee');
begin
  if not exists (
    select 1 from public.delegations where id = p_delegation_id and delegator_id = v_employee_id
  ) then
    perform private.fail('delegation_not_found');
  end if;

  perform private.lock_wallet(v_employee_id);
  perform private.end_delegation(p_delegation_id);

  return jsonb_build_object('ok', true);
end;
$$;

create function public.mark_password_changed()
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  update public.profiles set must_change_password = false where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- No-show settlement (run by pg_cron)
-- ---------------------------------------------------------------------------

-- Wallets are visited in employee order to keep the global lock order. The status
-- re-check makes repeat runs harmless: a settled booking is never charged twice.
create function private.settle_no_shows(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select b.id, b.employee_id, b.amount
    from public.bookings b
    join public.meal_offerings o on o.id = b.offering_id
    where b.status = 'booked' and o.pickup_until <= now()
    order by b.employee_id, b.id
    limit p_limit
  loop
    perform private.lock_wallet(v_row.employee_id);

    update public.bookings
    set status = 'no_show', settled_at = now()
    where id = v_row.id and status = 'booked';

    if found then
      perform private.post_tx(v_row.employee_id, 'settle_no_show', 0, -v_row.amount, v_row.id);
      perform private.revoke_booking_tokens(v_row.id);
      perform private.notify(v_row.employee_id, 'meal_not_collected', jsonb_build_object('booking_id', v_row.id));
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
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
grant execute on function public.redeem_pickup(text, uuid) to authenticated;
grant execute on function public.redeem_short_code(text, uuid) to authenticated;
grant execute on function public.record_manual_delivery(uuid, text, uuid) to authenticated;
grant execute on function public.my_pickups() to authenticated;
grant execute on function public.find_colleague(text) to authenticated;
grant execute on function public.set_delegation(text, uuid, uuid) to authenticated;
grant execute on function public.revoke_delegation(uuid) to authenticated;
grant execute on function public.mark_password_changed() to authenticated;
