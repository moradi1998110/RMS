-- Turning schedules into dated offerings, Ramadan rules, restaurant cancellation
-- and the recurring jobs.

create function private.at_offset(p_date date, p_day_offset integer, p_time time, p_timezone text)
returns timestamptz
language sql
stable
as $$
  select ((p_date + p_day_offset) + p_time) at time zone p_timezone;
$$;

create function private.is_ramadan(p_date date)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.ramadan_periods where p_date between start_date and end_date
  );
$$;

-- Generates the coming days. Existing offerings are left untouched, so running this
-- again, or editing a schedule, never alters what people have already booked.
create function private.generate_offerings(p_restaurant_id uuid default null, p_days integer default 14)
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
    private.at_offset(d.service_date, s.book_day_offset, s.book_time, r.timezone),
    private.at_offset(d.service_date, s.cancel_day_offset, s.cancel_time, r.timezone),
    private.at_offset(d.service_date, s.pickup_from_day_offset, s.pickup_from_time, r.timezone),
    private.at_offset(d.service_date, s.pickup_until_day_offset, s.pickup_until_time, r.timezone),
    s.capacity
  from public.schedules s
  join public.meals m on m.id = s.meal_id and m.is_active
  join public.restaurants r on r.id = s.restaurant_id and r.is_active
  cross join lateral (
    select g.value::date as service_date
    from generate_series(
      greatest(s.start_date, (now() at time zone r.timezone)::date)::timestamp,
      least(
        coalesce(s.end_date, 'infinity'::date),
        (now() at time zone r.timezone)::date + p_days
      )::timestamp,
      interval '1 day'
    ) as g(value)
  ) d
  where s.is_active
    and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
    and extract(dow from d.service_date)::smallint = any (s.weekdays)
    and (s.season = 'ramadan') = private.is_ramadan(d.service_date)
    and private.at_offset(d.service_date, s.pickup_until_day_offset, s.pickup_until_time, r.timezone) > now()
  on conflict (meal_id, service_date, period) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- The manager's "publish" button.
create function public.publish_schedule()
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  perform private.require_role('manager');
  return jsonb_build_object('created', private.generate_offerings(private.my_restaurant_id()));
end;
$$;

-- Cancels an offering and refunds everyone who has not collected yet. Meals already
-- collected stay settled.
create function private.cancel_offering(p_offering_id uuid, p_reason text)
returns integer
language plpgsql
as $$
declare
  v_booking public.bookings;
  v_count integer := 0;
begin
  perform 1
  from public.wallets
  where employee_id in (
    select employee_id from public.bookings where offering_id = p_offering_id and status = 'booked'
  )
  order by employee_id
  for update;

  update public.meal_offerings
  set status = 'cancelled', cancel_reason = p_reason
  where id = p_offering_id and status = 'open';

  if not found then
    return 0;
  end if;

  for v_booking in
    select * from public.bookings where offering_id = p_offering_id and status = 'booked' order by id for update
  loop
    update public.bookings
    set status = 'cancelled_by_restaurant', cancelled_at = now()
    where id = v_booking.id;

    perform private.post_tx(v_booking.employee_id, 'release', v_booking.amount, -v_booking.amount, v_booking.id, p_reason);
    perform private.revoke_booking_tokens(v_booking.id);
    perform private.notify(v_booking.employee_id, 'meal_cancelled', jsonb_build_object(
      'booking_id', v_booking.id, 'refunded', v_booking.amount, 'reason', p_reason
    ));
    v_count := v_count + 1;
  end loop;

  update public.meal_offerings
  set booked_count = booked_count - v_count
  where id = p_offering_id;

  return v_count;
end;
$$;

create function public.cancel_offering(p_offering_id uuid, p_reason text, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_previous jsonb;
  v_offering public.meal_offerings;
  v_refunded integer;
begin
  perform private.require_role('manager', 'admin');

  v_previous := private.idem_begin('cancel_offering', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    perform private.fail('reason_required');
  end if;

  select * into v_offering from public.meal_offerings where id = p_offering_id;

  if not found or not (private.is_admin() or private.manages(v_offering.restaurant_id)) then
    perform private.fail('offering_not_found');
  end if;
  if now() >= v_offering.pickup_until then
    perform private.fail('offering_finished');
  end if;

  v_refunded := private.cancel_offering(p_offering_id, p_reason);
  perform private.audit('cancel_offering', 'meal_offering', p_offering_id::text, jsonb_build_object(
    'reason', p_reason, 'refunded_bookings', v_refunded
  ));

  return private.idem_finish('cancel_offering', p_key, jsonb_build_object('refunded_bookings', v_refunded));
end;
$$;

-- ---------------------------------------------------------------------------
-- Ramadan dates
-- ---------------------------------------------------------------------------

-- Offerings that would no longer belong if this period were saved: normal meals
-- inside Ramadan, and Ramadan meals outside it.
create function private.ramadan_conflicts(p_hijri_year integer, p_start date, p_end date)
returns setof uuid
language sql
stable
as $$
  select o.id
  from public.meal_offerings o
  where o.status = 'open'
    and o.pickup_until > now()
    and (o.season = 'ramadan') <> (
      o.service_date between p_start and p_end
      or exists (
        select 1 from public.ramadan_periods r
        where r.hijri_year <> p_hijri_year and o.service_date between r.start_date and r.end_date
      )
    );
$$;

-- Shown to the admin before confirming a change (e.g. after the moon sighting).
create function public.preview_ramadan_change(p_hijri_year integer, p_start date, p_end date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
begin
  perform private.require_role('admin');

  if p_start is null or p_end is null or p_start > p_end then
    perform private.fail('invalid_dates');
  end if;

  return jsonb_build_object(
    'offerings', (select count(*) from private.ramadan_conflicts(p_hijri_year, p_start, p_end)),
    'bookings_to_refund', (
      select count(*)
      from public.bookings
      where status = 'booked'
        and offering_id in (select private.ramadan_conflicts(p_hijri_year, p_start, p_end))
    )
  );
end;
$$;

create function public.set_ramadan_period(p_hijri_year integer, p_start date, p_end date, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_previous jsonb;
  v_id uuid;
  v_offerings integer := 0;
  v_refunded integer := 0;
begin
  perform private.require_role('admin');

  v_previous := private.idem_begin('set_ramadan_period', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  if p_start is null or p_end is null or p_start > p_end then
    perform private.fail('invalid_dates');
  end if;

  if exists (
    select 1 from public.ramadan_periods
    where hijri_year <> p_hijri_year and start_date <= p_end and end_date >= p_start
  ) then
    perform private.fail('overlapping_period');
  end if;

  for v_id in
    select id from private.ramadan_conflicts(p_hijri_year, p_start, p_end) as id order by id
  loop
    v_refunded := v_refunded + private.cancel_offering(v_id, 'ramadan_dates_changed');
    v_offerings := v_offerings + 1;
  end loop;

  insert into public.ramadan_periods (hijri_year, start_date, end_date)
  values (p_hijri_year, p_start, p_end)
  on conflict (hijri_year) do update
  set start_date = excluded.start_date, end_date = excluded.end_date;

  perform private.generate_offerings();
  perform private.audit('set_ramadan_period', 'ramadan_period', p_hijri_year::text, jsonb_build_object(
    'start_date', p_start, 'end_date', p_end,
    'cancelled_offerings', v_offerings, 'refunded_bookings', v_refunded
  ));

  return private.idem_finish('set_ramadan_period', p_key, jsonb_build_object(
    'cancelled_offerings', v_offerings,
    'refunded_bookings', v_refunded
  ));
end;
$$;

-- ---------------------------------------------------------------------------
-- Nightly integrity check
-- ---------------------------------------------------------------------------

-- Each wallet must equal the sum of its ledger, and held must equal the employee's
-- open bookings. Any difference is recorded and every admin is alerted.
create function private.check_wallet_integrity()
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_count integer;
begin
  insert into public.integrity_alerts (employee_id, details)
  select
    w.employee_id,
    jsonb_build_object(
      'available', w.available,
      'held', w.held,
      'ledger_available', coalesce(t.available, 0),
      'ledger_held', coalesce(t.held, 0),
      'open_bookings', coalesce(b.held, 0)
    )
  from public.wallets w
  left join (
    select employee_id, sum(available_delta) as available, sum(held_delta) as held
    from public.wallet_transactions
    group by employee_id
  ) t on t.employee_id = w.employee_id
  left join (
    select employee_id, sum(amount) as held
    from public.bookings
    where status = 'booked'
    group by employee_id
  ) b on b.employee_id = w.employee_id
  where w.available <> coalesce(t.available, 0)
     or w.held <> coalesce(t.held, 0)
     or w.held <> coalesce(b.held, 0);

  get diagnostics v_count = row_count;

  if v_count > 0 then
    insert into public.notifications (user_id, type, payload)
    select id, 'integrity_alert', jsonb_build_object('wallets', v_count)
    from public.profiles
    where role = 'admin' and is_active;
  end if;

  return v_count;
end;
$$;

create function private.purge_expired_keys()
returns void
language sql
as $$
  delete from private.idempotency_keys where created_at < now() - interval '30 days';
  delete from private.colleague_lookups where created_at < now() - interval '1 day';
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
grant execute on function public.publish_schedule() to authenticated;
grant execute on function public.cancel_offering(uuid, text, uuid) to authenticated;
grant execute on function public.preview_ramadan_change(integer, date, date) to authenticated;
grant execute on function public.set_ramadan_period(integer, date, date, uuid) to authenticated;

-- Recurring jobs. Times are UTC.
create extension if not exists pg_cron;

select cron.schedule('settle-no-shows', '*/5 * * * *', $$select private.settle_no_shows()$$);
select cron.schedule('generate-offerings', '10 0 * * *', $$select private.generate_offerings()$$);
select cron.schedule('check-wallet-integrity', '0 1 * * *', $$select private.check_wallet_integrity()$$);
select cron.schedule('purge-expired-keys', '30 1 * * *', $$select private.purge_expired_keys()$$);
