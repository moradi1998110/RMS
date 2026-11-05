-- Codes are sent only while their pickup is open: the user's own meal and the meals
-- colleagues delegated to them. A code for a later meal never leaves the server early.

create or replace function public.my_pickups()
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
    and o.pickup_from <= now()
    and o.pickup_until > now()
  order by b.employee_id = auth.uid() desc, o.pickup_from, p.full_name;
$$;
