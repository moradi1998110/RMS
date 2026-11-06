-- Employees rate a meal they collected, once, with stars, quick tags and a comment.
-- Rating opens an hour after pickup, once the meal has been eaten, and closes when the
-- restaurant's next pickup starts. It stays open at least two hours and at most a day,
-- so a suhoor collected at night can still be rated after it is eaten.

alter table public.bookings
  add column rate_from timestamptz,
  add column rate_until timestamptz;

-- Fixed at pickup, so later changes to meal times never move an open rating.
create function private.set_rating_window()
returns trigger
language plpgsql
as $$
declare
  v_next timestamptz;
begin
  if new.status = 'picked_up' and old.status is distinct from 'picked_up' then
    new.rate_from := new.picked_up_at + interval '1 hour';

    select min(pickup_from) into v_next
    from public.meal_offerings
    where restaurant_id = new.restaurant_id
      and status = 'open'
      and pickup_from > new.picked_up_at;

    new.rate_until := least(
      new.rate_from + interval '24 hours',
      greatest(coalesce(v_next, new.rate_from + interval '24 hours'), new.rate_from + interval '2 hours')
    );
  end if;
  return new;
end;
$$;

create trigger bookings_rating_window
  before update of status on public.bookings
  for each row execute function private.set_rating_window();

create table public.meal_ratings (
  booking_id uuid primary key references public.bookings (id),
  employee_id uuid not null references public.profiles (id),
  restaurant_id uuid not null references public.restaurants (id),
  meal_id uuid not null references public.meals (id),
  stars smallint not null check (stars between 1 and 5),
  tags text[] not null default '{}'
    check (tags <@ array['tasty', 'good_portion', 'small_portion', 'cold', 'late', 'clean']::text[]),
  comment text check (comment is null or char_length(comment) <= 500),
  created_at timestamptz not null default now()
);

create index meal_ratings_restaurant_idx on public.meal_ratings (restaurant_id, created_at desc);

-- Written only through rate_meal.
alter table public.meal_ratings enable row level security;
create policy meal_ratings_read on public.meal_ratings for select to authenticated
  using (employee_id = auth.uid() or private.is_admin() or private.manages(restaurant_id));

create function public.rate_meal(p_booking_id uuid, p_stars integer, p_tags text[], p_comment text, p_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_employee_id uuid := private.require_role('employee');
  v_previous jsonb;
  v_booking public.bookings;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  v_tags text[] := coalesce(p_tags, '{}');
begin
  v_previous := private.idem_begin('rate_meal', p_key);
  if v_previous is not null then
    return v_previous;
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id and employee_id = v_employee_id
  for update;

  if not found then
    perform private.fail('booking_not_found');
  end if;
  if v_booking.status <> 'picked_up' or v_booking.rate_from is null then
    perform private.fail('not_ratable');
  end if;
  if now() < v_booking.rate_from then
    perform private.fail('rating_not_open', jsonb_build_object('rate_from', v_booking.rate_from));
  end if;
  if now() >= v_booking.rate_until then
    perform private.fail('rating_closed');
  end if;
  if exists (select 1 from public.meal_ratings where booking_id = p_booking_id) then
    perform private.fail('already_rated');
  end if;
  if p_stars is null or p_stars not between 1 and 5 then
    perform private.fail('invalid_stars');
  end if;
  if not v_tags <@ array['tasty', 'good_portion', 'small_portion', 'cold', 'late', 'clean']::text[] then
    perform private.fail('invalid_tags');
  end if;
  if char_length(v_comment) > 500 then
    perform private.fail('comment_too_long');
  end if;

  insert into public.meal_ratings (booking_id, employee_id, restaurant_id, meal_id, stars, tags, comment)
  select v_booking.id, v_employee_id, v_booking.restaurant_id, o.meal_id, p_stars, v_tags, v_comment
  from public.meal_offerings o
  where o.id = v_booking.offering_id;

  return private.idem_finish('rate_meal', p_key, jsonb_build_object('ok', true));
end;
$$;

-- Collected meals the user can rate right now.
create function public.my_ratable_meals()
returns table (
  booking_id uuid,
  meal_name text,
  period public.meal_period,
  service_date date,
  picked_up_at timestamptz,
  rate_until timestamptz
)
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select b.id, m.name, o.period, o.service_date, b.picked_up_at, b.rate_until
  from public.bookings b
  join public.meal_offerings o on o.id = b.offering_id
  join public.meals m on m.id = o.meal_id
  where b.employee_id = auth.uid()
    and private.app_role() = 'employee'
    and b.status = 'picked_up'
    and b.rate_from <= now()
    and b.rate_until > now()
    and not exists (select 1 from public.meal_ratings r where r.booking_id = b.id)
  order by b.picked_up_at;
$$;

-- Ratings given in a time range: a manager sees their restaurant, the admin sees all.
create function public.meal_ratings_between(p_from timestamptz, p_until timestamptz)
returns table (
  booking_id uuid,
  restaurant_name text,
  meal_id uuid,
  meal_name text,
  period public.meal_period,
  service_date date,
  employee_name text,
  stars smallint,
  tags text[],
  comment text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
begin
  perform private.require_role('manager', 'admin');
  return query
  select r.booking_id, rest.name, r.meal_id, m.name, o.period, o.service_date, p.full_name,
         r.stars, r.tags, r.comment, r.created_at
  from public.meal_ratings r
  join public.bookings b on b.id = r.booking_id
  join public.meal_offerings o on o.id = b.offering_id
  join public.meals m on m.id = r.meal_id
  join public.profiles p on p.id = r.employee_id
  join public.restaurants rest on rest.id = r.restaurant_id
  where r.created_at >= p_from
    and r.created_at < p_until
    and (private.is_admin() or private.manages(r.restaurant_id))
  order by r.created_at desc;
end;
$$;

revoke all on function private.set_rating_window() from public, anon, authenticated;
revoke all on function public.rate_meal(uuid, integer, text[], text, uuid) from public, anon, authenticated;
revoke all on function public.my_ratable_meals() from public, anon, authenticated;
revoke all on function public.meal_ratings_between(timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.rate_meal(uuid, integer, text[], text, uuid) to authenticated;
grant execute on function public.my_ratable_meals() to authenticated;
grant execute on function public.meal_ratings_between(timestamptz, timestamptz) to authenticated;
