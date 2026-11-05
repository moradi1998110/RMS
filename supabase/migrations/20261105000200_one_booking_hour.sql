-- Each meal now has one hour, on the day it is collected, when booking and cancelling
-- for that day stop, so the restaurant can count the meals and prepare them. Other days
-- stay open. The app sends the same hour for both, and set_meal_times keeps its shape.

create or replace function private.seed_time_defaults(p_restaurant_id uuid)
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
         v.from_day, v.stop_at::time, v.from_day, v.stop_at::time,
         v.from_day, v.from_at::time, v.until_day, v.until_at::time
  from (values
    ('breakfast', 'normal',  '05:00',  0, '06:30',  0, '09:00'),
    ('lunch',     'normal',  '10:00',  0, '12:00',  0, '14:30'),
    ('dinner',    'normal',  '16:00',  0, '18:00',  0, '20:30'),
    ('suhoor',    'ramadan', '19:00', -1, '21:00', -1, '23:30'),
    ('iftar',     'ramadan', '14:00',  0, '17:00',  0, '19:30')
  ) as v(period, season, stop_at, from_day, from_at, until_day, until_at)
  on conflict (restaurant_id, period, season) do nothing;
$$;

-- Moves restaurants already set up to the new hours.
update public.time_defaults t
set book_day_offset = t.pickup_from_day_offset,
    book_time = v.stop_at::time,
    cancel_day_offset = t.pickup_from_day_offset,
    cancel_time = v.stop_at::time
from (values
  ('breakfast', '05:00'),
  ('lunch', '10:00'),
  ('dinner', '16:00'),
  ('suhoor', '19:00'),
  ('iftar', '14:00')
) as v(period, stop_at)
where t.period = v.period::public.meal_period;

-- Dated meals nobody has booked follow at once. Booked meals keep what was agreed.
update public.meal_offerings o
set book_until = private.at_offset(o.service_date, t.book_day_offset, t.book_time, r.timezone),
    cancel_until = private.at_offset(o.service_date, t.cancel_day_offset, t.cancel_time, r.timezone)
from public.schedules s, public.time_defaults t, public.restaurants r
where s.id = o.schedule_id
  and s.book_time is null
  and t.restaurant_id = o.restaurant_id and t.period = o.period
  and r.id = o.restaurant_id
  and o.status = 'open'
  and o.booked_count = 0
  and o.pickup_until > now();
