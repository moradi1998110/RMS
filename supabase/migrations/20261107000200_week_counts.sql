-- The weekly reports used to download every booking of the week to count them on the
-- phone. This counts them here instead and sends one row per day, meal, period,
-- status and restaurant: a few hundred rows however many people booked.

create index if not exists meal_offerings_date_idx on public.meal_offerings (service_date);

-- Admins see every restaurant, a manager only their own, anyone else nothing.
create function public.booking_week_counts(p_start date)
returns table (
  service_date date,
  period public.meal_period,
  status public.booking_status,
  restaurant_id uuid,
  meal_name text,
  bookings integer,
  amount bigint
)
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select o.service_date, o.period, b.status, b.restaurant_id, m.name, count(*)::integer, sum(b.amount)::bigint
  from public.bookings b
  join public.meal_offerings o on o.id = b.offering_id
  join public.meals m on m.id = o.meal_id
  where o.service_date >= p_start
    and o.service_date < p_start + 7
    and (
      private.app_role() = 'admin'
      or (private.app_role() = 'manager' and b.restaurant_id = private.my_restaurant_id())
    )
  group by o.service_date, o.period, b.status, b.restaurant_id, m.name
  order by o.service_date, o.period, m.name;
$$;

revoke all on function public.booking_week_counts(date) from public, anon, authenticated;
grant execute on function public.booking_week_counts(date) to authenticated;
