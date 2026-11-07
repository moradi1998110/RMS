-- Weekly report counts: totals are right, and each role sees only what it may.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create schema test_util;
grant usage on schema test_util to public;

create function test_util.id(p_name text) returns uuid
language sql immutable as $$ select md5(p_name)::uuid; $$;

create function test_util.login(p_name text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', test_util.id(p_name), 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

grant execute on all functions in schema test_util to public;

insert into public.sites (id, name) values (test_util.id('site'), 'Site');
insert into public.restaurants (id, site_id, name, timezone) values
  (test_util.id('rest1'), test_util.id('site'), 'One', 'Asia/Baghdad'),
  (test_util.id('rest2'), test_util.id('site'), 'Two', 'Asia/Baghdad');

insert into auth.users (id, email)
  select test_util.id(name), name || '@meals.invalid'
  from unnest(array['admin', 'mgr1', 'emp1', 'emp2', 'emp3']) as name;
insert into public.profiles (id, username, full_name, role, site_id, restaurant_id) values
  (test_util.id('admin'), 'admin', 'Admin', 'admin', null, null),
  (test_util.id('mgr1'), 'mgr1', 'Manager', 'manager', test_util.id('site'), test_util.id('rest1')),
  (test_util.id('emp1'), 'emp1', 'One', 'employee', test_util.id('site'), test_util.id('rest1')),
  (test_util.id('emp2'), 'emp2', 'Two', 'employee', test_util.id('site'), test_util.id('rest1')),
  (test_util.id('emp3'), 'emp3', 'Three', 'employee', test_util.id('site'), test_util.id('rest2'));

insert into public.meals (id, restaurant_id, name, price) values
  (test_util.id('rice'), test_util.id('rest1'), 'Rice', 5000),
  (test_util.id('soup'), test_util.id('rest2'), 'Soup', 3000);
insert into public.meal_offerings (
  id, meal_id, restaurant_id, service_date, period, season, price,
  book_until, cancel_until, pickup_from, pickup_until
) values
  (test_util.id('rice-day'), test_util.id('rice'), test_util.id('rest1'), date '2026-11-07', 'lunch', 'normal', 5000,
   timestamptz '2026-11-07 07:00+03', timestamptz '2026-11-07 07:00+03', timestamptz '2026-11-07 12:00+03', timestamptz '2026-11-07 14:30+03'),
  (test_util.id('soup-day'), test_util.id('soup'), test_util.id('rest2'), date '2026-11-08', 'dinner', 'normal', 3000,
   timestamptz '2026-11-08 16:00+03', timestamptz '2026-11-08 16:00+03', timestamptz '2026-11-08 18:00+03', timestamptz '2026-11-08 20:30+03'),
  (test_util.id('rice-later'), test_util.id('rice'), test_util.id('rest1'), date '2026-11-14', 'lunch', 'normal', 5000,
   timestamptz '2026-11-14 07:00+03', timestamptz '2026-11-14 07:00+03', timestamptz '2026-11-14 12:00+03', timestamptz '2026-11-14 14:30+03');

-- Written directly: these tests are about counting, not about booking rules.
insert into public.bookings (employee_id, offering_id, restaurant_id, amount, status, picked_up_at, picked_up_by, pickup_method) values
  (test_util.id('emp1'), test_util.id('rice-day'), test_util.id('rest1'), 5000, 'picked_up', now(), test_util.id('emp1'), 'scan'),
  (test_util.id('emp2'), test_util.id('rice-day'), test_util.id('rest1'), 5000, 'picked_up', now(), test_util.id('emp2'), 'scan'),
  (test_util.id('emp3'), test_util.id('soup-day'), test_util.id('rest2'), 3000, 'booked', null, null, null),
  (test_util.id('emp1'), test_util.id('rice-later'), test_util.id('rest1'), 5000, 'booked', null, null, null);

select test_util.login('admin');
select is((select sum(bookings)::integer from public.booking_week_counts(date '2026-11-07')), 2 + 1,
  'the admin counts every restaurant, within the seven days');
select is((select bookings from public.booking_week_counts(date '2026-11-07') where meal_name = 'Rice'), 2,
  'two collected rice lunches are one row of two');
select is((select amount from public.booking_week_counts(date '2026-11-07') where meal_name = 'Rice'), 10000::bigint,
  'with their total amount');

select test_util.login('mgr1');
select is((select array_agg(distinct meal_name) from public.booking_week_counts(date '2026-11-07')), array['Rice'],
  'a manager sees only their restaurant');

select test_util.login('emp1');
select is((select count(*)::integer from public.booking_week_counts(date '2026-11-07')), 0, 'an employee sees nothing');

select * from finish();
rollback;
