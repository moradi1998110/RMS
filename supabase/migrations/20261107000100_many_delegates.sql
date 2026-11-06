-- An employee can let up to five colleagues collect their meals. Each one gets a code
-- for every meal once its pickup starts. A meal collected by anyone stays on everyone's
-- codes screen as collected, with who took it, until its pickup ends.

drop index public.delegations_one_standing;

create unique index delegations_one_standing_per_delegate
  on public.delegations (delegator_id, delegate_id)
  where scope = 'standing' and revoked_at is null;

-- p_booking_id set: this meal only. Null: all my meals until I revoke, alongside any
-- colleagues already chosen. Choosing someone already chosen changes nothing.
create or replace function public.set_delegation(p_delegate_username text, p_booking_id uuid, p_key uuid)
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

  -- Serializes with book_meals, which reads the standing delegations under this lock.
  perform private.lock_wallet(v_employee_id);

  if p_booking_id is null then
    select id into v_delegation_id
    from public.delegations
    where delegator_id = v_employee_id and delegate_id = v_delegate.id
      and scope = 'standing' and revoked_at is null;

    if v_delegation_id is not null then
      return private.idem_finish('set_delegation', p_key, jsonb_build_object(
        'delegation_id', v_delegation_id,
        'delegate_name', v_delegate.full_name
      ));
    end if;

    if (select count(*) from public.delegations
        where delegator_id = v_employee_id and scope = 'standing' and revoked_at is null) >= 5 then
      perform private.fail('too_many_delegates');
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

-- Same as before, except every standing delegate gets a code for each new meal.
create or replace function public.book_meals(p_offering_ids uuid[], p_key uuid)
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

    for v_standing in
      select d.id, d.delegate_id
      from public.delegations d
      join public.profiles p on p.id = d.delegate_id and p.is_active
      where d.delegator_id = v_employee_id and d.scope = 'standing' and d.revoked_at is null
      order by d.id
    loop
      perform private.issue_token(v_booking_id, v_standing.delegate_id, v_offering.restaurant_id, v_standing.id);
    end loop;

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

-- The colleagues who can collect my meals, oldest first.
create function public.my_delegates()
returns table (
  delegation_id uuid,
  username text,
  full_name text,
  department text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select d.id, p.username, p.full_name, p.department, d.created_at
  from public.delegations d
  join public.profiles p on p.id = d.delegate_id
  where d.delegator_id = auth.uid()
    and private.app_role() = 'employee'
    and d.scope = 'standing'
    and d.revoked_at is null
  order by d.created_at, d.id;
$$;

-- Codes for meals being collected now. A meal already collected comes back without
-- its code, with when and by whom, to the owner and every colleague still chosen.
-- A colleague whose delegation was withdrawn no longer sees it.
drop function public.my_pickups();

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
  pickup_until timestamptz,
  picked_up_at timestamptz,
  picked_up_by_name text
)
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select *
  from (
    select distinct on (b.id)
      b.id as booking_id,
      case when b.status = 'booked' then t.token end as token,
      case when b.status = 'booked' then t.short_code end as short_code,
      b.employee_id = auth.uid() as is_mine,
      p.full_name as owner_name,
      m.name as meal_name,
      o.period,
      o.service_date,
      o.pickup_from,
      o.pickup_until,
      b.picked_up_at,
      (select full_name from public.profiles where id = b.picked_up_by) as picked_up_by_name
    from public.pickup_tokens t
    join public.bookings b on b.id = t.booking_id
    join public.meal_offerings o on o.id = b.offering_id
    join public.meals m on m.id = o.meal_id
    join public.profiles p on p.id = b.employee_id
    where t.holder_id = auth.uid()
      and private.app_role() = 'employee'
      and o.status = 'open'
      and o.pickup_from <= now()
      and o.pickup_until > now()
      and (
        (b.status = 'booked' and t.revoked_at is null)
        or (b.status = 'picked_up' and (
          t.delegation_id is null
          or exists (select 1 from public.delegations d where d.id = t.delegation_id and d.revoked_at is null)
        ))
      )
    order by b.id, t.revoked_at is null desc
  ) as codes
  order by is_mine desc, pickup_from, owner_name;
$$;

revoke all on function public.my_delegates() from public, anon, authenticated;
revoke all on function public.my_pickups() from public, anon, authenticated;
grant execute on function public.my_delegates() to authenticated;
grant execute on function public.my_pickups() to authenticated;
