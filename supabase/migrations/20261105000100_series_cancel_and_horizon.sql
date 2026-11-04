-- Booking a whole month needs offerings further ahead, and the app can cancel a
-- repeated meal in one step. Publishing further ahead also means a schedule or meal
-- edit must reach meals already generated, or stale copies would stay for weeks.

create or replace function private.generate_offerings(p_restaurant_id uuid default null, p_days integer default null)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_count integer;
begin
  insert into public.meal_offerings (
    schedule_id, meal_id, restaurant_id, service_date, period, season, price,
    book_until, cancel_until, pickup_from, pickup_until, capacity
  )
  select
    s.id, s.meal_id, s.restaurant_id, d.service_date, s.period, s.season, m.price,
    private.at_offset(d.service_date, coalesce(s.book_day_offset, t.book_day_offset), coalesce(s.book_time, t.book_time), r.timezone),
    private.at_offset(d.service_date, coalesce(s.cancel_day_offset, t.cancel_day_offset), coalesce(s.cancel_time, t.cancel_time), r.timezone),
    private.at_offset(d.service_date, coalesce(s.pickup_from_day_offset, t.pickup_from_day_offset), coalesce(s.pickup_from_time, t.pickup_from_time), r.timezone),
    private.at_offset(d.service_date, coalesce(s.pickup_until_day_offset, t.pickup_until_day_offset), coalesce(s.pickup_until_time, t.pickup_until_time), r.timezone),
    s.capacity
  from public.schedules s
  join public.meals m on m.id = s.meal_id and m.is_active
  join public.restaurants r on r.id = s.restaurant_id and r.is_active
  join public.time_defaults t on t.restaurant_id = s.restaurant_id and t.period = s.period and t.season = s.season
  cross join lateral (
    select g.value::date as service_date
    from generate_series(
      greatest(s.start_date, (now() at time zone r.timezone)::date)::timestamp,
      least(
        coalesce(s.end_date, 'infinity'::date),
        -- Through the end of next month, so a whole month can always be booked.
        coalesce(
          (now() at time zone r.timezone)::date + p_days,
          (date_trunc('month', now() at time zone r.timezone) + interval '2 months - 1 day')::date
        )
      )::timestamp,
      interval '1 day'
    ) as g(value)
  ) d
  where s.is_active
    and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
    and extract(dow from d.service_date)::smallint = any (s.weekdays)
    and (s.season = 'ramadan') = private.is_ramadan(d.service_date)
    and private.at_offset(
          d.service_date,
          coalesce(s.pickup_until_day_offset, t.pickup_until_day_offset),
          coalesce(s.pickup_until_time, t.pickup_until_time),
          r.timezone
        ) > now()
  on conflict (meal_id, service_date, period) do update
  set schedule_id = excluded.schedule_id,
      season = excluded.season,
      price = excluded.price,
      book_until = excluded.book_until,
      cancel_until = excluded.cancel_until,
      pickup_from = excluded.pickup_from,
      pickup_until = excluded.pickup_until,
      capacity = excluded.capacity,
      status = 'open',
      cancel_reason = null
  -- Brings back only what the system withdrew. A meal the restaurant cancelled by
  -- hand stays cancelled.
  where meal_offerings.status = 'cancelled'
    and meal_offerings.booked_count = 0
    and meal_offerings.cancel_reason in ('schedule_changed', 'ramadan_dates_changed');

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Withdraws this schedule's meals that nobody holds, then generates them afresh from
-- the current schedule and meal. Meals with bookings keep what their bookers agreed to.
create function private.resync_schedule(p_schedule_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_restaurant_id uuid;
begin
  select restaurant_id into v_restaurant_id from public.schedules where id = p_schedule_id;

  update public.meal_offerings
  set status = 'cancelled', cancel_reason = 'schedule_changed'
  where schedule_id = p_schedule_id
    and status = 'open'
    and booked_count = 0
    and pickup_until > now();

  perform private.generate_offerings(v_restaurant_id);
end;
$$;

create function private.schedule_changed()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  perform private.resync_schedule(new.id);
  return new;
end;
$$;

create trigger schedules_resync
  after update on public.schedules
  for each row execute function private.schedule_changed();

create function private.meal_changed()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_schedule_id uuid;
begin
  for v_schedule_id in select id from public.schedules where meal_id = new.id order by id loop
    perform private.resync_schedule(v_schedule_id);
  end loop;
  return new;
end;
$$;

create trigger meals_resync
  after update of price, is_active on public.meals
  for each row
  when (old.price is distinct from new.price or old.is_active is distinct from new.is_active)
  execute function private.meal_changed();

-- Cancels a booking and the same meal on the same weekday later in that month. Meals
-- past their own cancel deadline are skipped and reported, since the rule for each
-- meal still applies. The chosen booking itself must still be cancellable.
create function public.cancel_booking_series(p_booking_id uuid, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_employee_id uuid := private.require_role('employee');
  v_previous jsonb;
  v_wallet public.wallets;
  v_target_offering public.meal_offerings;
  v_booking public.bookings;
  v_row record;
  v_cancelled integer := 0;
  v_refunded bigint := 0;
  v_skipped integer;
begin
  v_previous := private.idem_begin('cancel_booking_series', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  v_wallet := private.lock_wallet(v_employee_id);

  select o.* into v_target_offering
  from public.meal_offerings o
  where o.id = (select offering_id from public.bookings where id = p_booking_id and employee_id = v_employee_id);

  if not found then
    perform private.fail('booking_not_found');
  end if;

  -- Offerings before bookings, in id order, as everywhere else.
  perform 1
  from public.meal_offerings o
  where o.meal_id = v_target_offering.meal_id
    and o.period = v_target_offering.period
    and o.service_date >= v_target_offering.service_date
    and date_trunc('month', o.service_date) = date_trunc('month', v_target_offering.service_date)
    and extract(dow from o.service_date) = extract(dow from v_target_offering.service_date)
    and exists (
      select 1 from public.bookings b
      where b.offering_id = o.id and b.employee_id = v_employee_id and b.status = 'booked'
    )
  order by o.id
  for update of o;

  select * into v_booking
  from public.bookings
  where id = p_booking_id and employee_id = v_employee_id
  for update;

  if v_booking.status <> 'booked' then
    perform private.fail('not_cancellable', jsonb_build_object('status', v_booking.status));
  end if;

  select * into v_target_offering from public.meal_offerings where id = v_booking.offering_id;

  if now() >= v_target_offering.cancel_until then
    perform private.fail('cancel_deadline_passed', jsonb_build_object('cancel_until', v_target_offering.cancel_until));
  end if;

  for v_row in
    select b.id, b.amount, b.offering_id
    from public.bookings b
    join public.meal_offerings o on o.id = b.offering_id
    where b.employee_id = v_employee_id
      and b.status = 'booked'
      and o.meal_id = v_target_offering.meal_id
      and o.period = v_target_offering.period
      and o.service_date >= v_target_offering.service_date
      and date_trunc('month', o.service_date) = date_trunc('month', v_target_offering.service_date)
      and extract(dow from o.service_date) = extract(dow from v_target_offering.service_date)
      and now() < o.cancel_until
    order by b.id
    for update of b
  loop
    update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_row.id;
    update public.meal_offerings set booked_count = booked_count - 1 where id = v_row.offering_id;
    perform private.post_tx(v_employee_id, 'release', v_row.amount, -v_row.amount, v_row.id);
    perform private.revoke_booking_tokens(v_row.id);
    v_cancelled := v_cancelled + 1;
    v_refunded := v_refunded + v_row.amount;
  end loop;

  select count(*) into v_skipped
  from public.bookings b
  join public.meal_offerings o on o.id = b.offering_id
  where b.employee_id = v_employee_id
    and b.status = 'booked'
    and o.meal_id = v_target_offering.meal_id
    and o.period = v_target_offering.period
    and o.service_date >= v_target_offering.service_date
    and date_trunc('month', o.service_date) = date_trunc('month', v_target_offering.service_date)
    and extract(dow from o.service_date) = extract(dow from v_target_offering.service_date);

  return private.idem_finish('cancel_booking_series', p_key, jsonb_build_object(
    'cancelled', v_cancelled,
    'refunded', v_refunded,
    'skipped', v_skipped,
    'available', v_wallet.available + v_refunded,
    'held', v_wallet.held - v_refunded
  ));
end;
$$;

revoke all on function private.resync_schedule(uuid) from public, anon, authenticated;
revoke all on function private.schedule_changed() from public, anon, authenticated;
revoke all on function private.meal_changed() from public, anon, authenticated;
revoke all on function public.cancel_booking_series(uuid, uuid) from public, anon, authenticated;
grant execute on function public.cancel_booking_series(uuid, uuid) to authenticated;
