-- Each restaurant has one rule per meal period for booking, cancelling and pickup.
-- A schedule follows its period's rule unless it stores explicit times of its own.

create function private.seed_time_defaults(p_restaurant_id uuid)
returns void
language sql
security definer
set search_path = public, private, pg_temp
as $$
  insert into public.time_defaults (
    restaurant_id, period, season,
    book_day_offset, book_time, cancel_day_offset, cancel_time,
    pickup_from_day_offset, pickup_from_time, pickup_until_day_offset, pickup_until_time
  )
  select p_restaurant_id, v.period::public.meal_period, v.season::public.season_type,
         v.book_day, v.book_at::time, v.cancel_day, v.cancel_at::time,
         v.from_day, v.from_at::time, v.until_day, v.until_at::time
  from (values
    ('breakfast', 'normal',  -1, '20:00', -1, '22:00',  0, '06:30',  0, '09:00'),
    ('lunch',     'normal',  -1, '20:00',  0, '08:00',  0, '12:00',  0, '14:30'),
    ('dinner',    'normal',   0, '12:00',  0, '14:00',  0, '18:00',  0, '20:30'),
    ('suhoor',    'ramadan', -1, '18:00', -1, '20:00', -1, '21:00', -1, '23:30'),
    ('iftar',     'ramadan',  0, '10:00',  0, '12:00',  0, '17:00',  0, '19:30')
  ) as v(period, season, book_day, book_at, cancel_day, cancel_at, from_day, from_at, until_day, until_at)
  on conflict (restaurant_id, period, season) do nothing;
$$;

create function private.restaurant_seed_time_defaults()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  perform private.seed_time_defaults(new.id);
  return new;
end;
$$;

create trigger restaurants_seed_time_defaults
  after insert on public.restaurants
  for each row execute function private.restaurant_seed_time_defaults();

select private.seed_time_defaults(id) from public.restaurants;

-- Null times now mean "follow the rule for this period".
alter table public.schedules
  alter column book_day_offset drop not null,
  alter column book_time drop not null,
  alter column cancel_day_offset drop not null,
  alter column cancel_time drop not null,
  alter column pickup_from_day_offset drop not null,
  alter column pickup_from_time drop not null,
  alter column pickup_until_day_offset drop not null,
  alter column pickup_until_time drop not null,
  add constraint schedules_times_all_or_none check (
    num_nulls(
      book_day_offset, book_time, cancel_day_offset, cancel_time,
      pickup_from_day_offset, pickup_from_time, pickup_until_day_offset, pickup_until_time
    ) in (0, 8)
  );

create or replace function private.generate_offerings(p_restaurant_id uuid default null, p_days integer default 14)
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
        (now() at time zone r.timezone)::date + p_days
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
  on conflict (meal_id, service_date, period) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- The manager changes a period's rule. Dated meals nobody has booked follow at once.
-- Booked meals keep the deadline their bookers agreed to.
create function public.set_meal_times(
  p_period public.meal_period,
  p_book_day_offset integer,
  p_book_time time,
  p_cancel_day_offset integer,
  p_cancel_time time,
  p_pickup_from_day_offset integer,
  p_pickup_from_time time,
  p_pickup_until_day_offset integer,
  p_pickup_until_time time
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_restaurant_id uuid;
  v_timezone text;
  v_updated integer;
  v_kept integer;
begin
  perform private.require_role('manager');
  v_restaurant_id := private.my_restaurant_id();

  if num_nulls(
       p_period, p_book_day_offset, p_book_time, p_cancel_day_offset, p_cancel_time,
       p_pickup_from_day_offset, p_pickup_from_time, p_pickup_until_day_offset, p_pickup_until_time
     ) > 0
     or private.offset_minutes(p_book_day_offset, p_book_time) > private.offset_minutes(p_pickup_from_day_offset, p_pickup_from_time)
     or private.offset_minutes(p_cancel_day_offset, p_cancel_time) > private.offset_minutes(p_pickup_from_day_offset, p_pickup_from_time)
     or private.offset_minutes(p_pickup_from_day_offset, p_pickup_from_time) >= private.offset_minutes(p_pickup_until_day_offset, p_pickup_until_time)
  then
    perform private.fail('invalid_times');
  end if;

  update public.time_defaults
  set book_day_offset = p_book_day_offset,
      book_time = p_book_time,
      cancel_day_offset = p_cancel_day_offset,
      cancel_time = p_cancel_time,
      pickup_from_day_offset = p_pickup_from_day_offset,
      pickup_from_time = p_pickup_from_time,
      pickup_until_day_offset = p_pickup_until_day_offset,
      pickup_until_time = p_pickup_until_time
  where restaurant_id = v_restaurant_id and period = p_period;

  select timezone into v_timezone from public.restaurants where id = v_restaurant_id;

  update public.meal_offerings o
  set book_until = private.at_offset(o.service_date, p_book_day_offset, p_book_time, v_timezone),
      cancel_until = private.at_offset(o.service_date, p_cancel_day_offset, p_cancel_time, v_timezone),
      pickup_from = private.at_offset(o.service_date, p_pickup_from_day_offset, p_pickup_from_time, v_timezone),
      pickup_until = private.at_offset(o.service_date, p_pickup_until_day_offset, p_pickup_until_time, v_timezone)
  from public.schedules s
  where s.id = o.schedule_id
    and s.book_time is null
    and o.restaurant_id = v_restaurant_id
    and o.period = p_period
    and o.status = 'open'
    and o.booked_count = 0
    and o.pickup_until > now();

  get diagnostics v_updated = row_count;

  select count(*) into v_kept
  from public.meal_offerings o
  join public.schedules s on s.id = o.schedule_id
  where s.book_time is null
    and o.restaurant_id = v_restaurant_id
    and o.period = p_period
    and o.status = 'open'
    and o.booked_count > 0
    and o.pickup_until > now();

  perform private.audit('set_meal_times', 'time_defaults', p_period::text, jsonb_build_object(
    'restaurant_id', v_restaurant_id,
    'cancel_day_offset', p_cancel_day_offset,
    'cancel_time', p_cancel_time,
    'updated_offerings', v_updated,
    'kept_booked_offerings', v_kept
  ));

  return jsonb_build_object('updated_offerings', v_updated, 'kept_booked_offerings', v_kept);
end;
$$;

-- Rules change only through set_meal_times, so dated meals always follow them.
drop policy time_defaults_manager_insert on public.time_defaults;
drop policy time_defaults_manager_update on public.time_defaults;
revoke insert, update on public.time_defaults from authenticated;

revoke all on function private.seed_time_defaults(uuid) from public, anon, authenticated;
revoke all on function private.restaurant_seed_time_defaults() from public, anon, authenticated;
revoke all on function public.set_meal_times(public.meal_period, integer, time, integer, time, integer, time, integer, time) from public, anon, authenticated;
grant execute on function public.set_meal_times(public.meal_period, integer, time, integer, time, integer, time, integer, time) to authenticated;
