-- Read-only picture of why meals can or cannot be booked. Holds no names of people,
-- no balances and no pickup codes.
select jsonb_build_object(
  'server_now', now(),
  'baghdad_now', now() at time zone 'Asia/Baghdad',
  'ramadan_periods', (
    select coalesce(jsonb_agg(r order by r.start_date), '[]') from public.ramadan_periods r
  ),
  'restaurants', (
    select coalesce(jsonb_agg(jsonb_build_object('name', name, 'timezone', timezone, 'active', is_active)), '[]')
    from public.restaurants
  ),
  'time_rules', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'restaurant', r.name, 'period', t.period,
      'book', t.book_day_offset || ' ' || t.book_time,
      'cancel', t.cancel_day_offset || ' ' || t.cancel_time,
      'from', t.pickup_from_day_offset || ' ' || t.pickup_from_time,
      'until', t.pickup_until_day_offset || ' ' || t.pickup_until_time
    ) order by r.name, t.period), '[]')
    from public.time_defaults t join public.restaurants r on r.id = t.restaurant_id
  ),
  'schedules', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'restaurant', r.name, 'meal', m.name, 'meal_active', m.is_active, 'period', s.period, 'season', s.season,
      'weekdays', s.weekdays, 'repeat', s.repeat_type, 'start', s.start_date, 'end', s.end_date,
      'active', s.is_active, 'own_times', s.book_time is not null
    ) order by r.name, m.name, s.created_at), '[]')
    from public.schedules s
    join public.meals m on m.id = s.meal_id
    join public.restaurants r on r.id = s.restaurant_id
  ),
  'offerings_by_state', (
    select coalesce(jsonb_agg(x order by x.restaurant, x.meal, x.first_day), '[]') from (
      select r.name as restaurant, m.name as meal, o.period, o.season, o.status, o.cancel_reason,
             o.book_until > now() as bookable_now, count(*) as days,
             min(o.service_date) as first_day, max(o.service_date) as last_day,
             sum(o.booked_count) as booked
      from public.meal_offerings o
      join public.meals m on m.id = o.meal_id
      join public.restaurants r on r.id = o.restaurant_id
      where o.service_date >= (now() at time zone 'Asia/Baghdad')::date
      group by r.name, m.name, o.period, o.season, o.status, o.cancel_reason, o.book_until > now()
    ) x
  ),
  'open_offerings_next_60_rows', (
    select coalesce(jsonb_agg(x), '[]') from (
      select o.service_date, r.name as restaurant, m.name as meal, o.period, o.booked_count, o.capacity,
             o.book_until at time zone r.timezone as book_until_local
      from public.meal_offerings o
      join public.meals m on m.id = o.meal_id
      join public.restaurants r on r.id = o.restaurant_id
      where o.status = 'open' and o.service_date >= (now() at time zone 'Asia/Baghdad')::date
      order by o.service_date, m.name
      limit 60
    ) x
  ),
  'bookings_by_status', (
    select coalesce(jsonb_object_agg(status, n), '{}') from (
      select status, count(*) as n from public.bookings group by status
    ) x
  ),
  'recent_admin_actions', (
    select coalesce(jsonb_agg(x), '[]') from (
      select action, details - 'employee_ids' as details, created_at
      from public.audit_log
      where action in ('set_ramadan_period', 'set_meal_times', 'cancel_offering')
      order by id desc
      limit 15
    ) x
  )
) as report;
