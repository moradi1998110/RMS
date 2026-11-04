-- Cancelling a repeated meal, publishing a whole month, and edits reaching unbooked meals.

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

create function test_util.logout() returns void
language plpgsql as $$
begin
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- The first of next month, so every date below falls in one month whatever today is.
create function test_util.base() returns date
language sql stable as $$ select (date_trunc('month', current_date) + interval '1 month')::date; $$;

create function test_util.balance(p_name text) returns text
language sql security definer set search_path = public as $$
  select available || '/' || held from public.wallets where employee_id = test_util.id(p_name);
$$;

create function test_util.status(p_employee text, p_offering text) returns text
language sql security definer set search_path = public as $$
  select status::text from public.bookings
  where employee_id = test_util.id(p_employee) and offering_id = test_util.id(p_offering);
$$;

create function test_util.booking(p_employee text, p_offering text) returns uuid
language sql security definer set search_path = public as $$
  select id from public.bookings
  where employee_id = test_util.id(p_employee) and offering_id = test_util.id(p_offering);
$$;

create function test_util.add_offering(p_name text, p_meal text, p_day integer, p_period public.meal_period default 'lunch', p_cancel_until timestamptz default null)
returns void
language sql as $$
  insert into public.meal_offerings (
    id, meal_id, restaurant_id, service_date, period, season, price,
    book_until, cancel_until, pickup_from, pickup_until
  )
  select test_util.id(p_name), m.id, m.restaurant_id, test_util.base() + p_day, p_period, 'normal'::public.season_type, m.price,
         now() + interval '1 day', coalesce(p_cancel_until, now() + interval '1 day'), now() + interval '2 days', now() + interval '3 days'
  from public.meals m where m.id = test_util.id(p_meal);
$$;

insert into public.sites (id, name) values (test_util.id('site'), 'Site');
insert into public.restaurants (id, site_id, name, timezone)
  values (test_util.id('rest'), test_util.id('site'), 'Restaurant', 'Asia/Baghdad');

insert into auth.users (id, email)
  select test_util.id(name), name || '@meals.invalid' from unnest(array['admin1', 'mgr1', 'emp1', 'emp2']) as name;
insert into public.profiles (id, username, full_name, role) values (test_util.id('admin1'), 'admin1', 'admin1', 'admin');
insert into public.profiles (id, username, full_name, role, site_id, restaurant_id) values
  (test_util.id('mgr1'), 'mgr1', 'mgr1', 'manager', test_util.id('site'), test_util.id('rest')),
  (test_util.id('emp1'), 'emp1', 'emp1', 'employee', test_util.id('site'), test_util.id('rest')),
  (test_util.id('emp2'), 'emp2', 'emp2', 'employee', test_util.id('site'), test_util.id('rest'));

insert into public.meals (id, restaurant_id, name, price) values
  (test_util.id('rice'), test_util.id('rest'), 'Rice', 1000),
  (test_util.id('fish'), test_util.id('rest'), 'Fish', 2000),
  (test_util.id('soup'), test_util.id('rest'), 'Soup', 500);

select test_util.add_offering('rice_w1', 'rice', 0);
select test_util.add_offering('rice_w2', 'rice', 7);
select test_util.add_offering('rice_w3', 'rice', 14, 'lunch', now() - interval '1 second');
select test_util.add_offering('rice_w4', 'rice', 21);
select test_util.add_offering('rice_other_day', 'rice', 1);
select test_util.add_offering('rice_next_month', 'rice', 35);
select test_util.add_offering('fish_w1', 'fish', 0);
select test_util.add_offering('rice_dinner', 'rice', 0, 'dinner');
select test_util.add_offering('fish_a', 'fish', 2);
select test_util.add_offering('fish_b', 'fish', 9);
select test_util.add_offering('fish_c', 'fish', 16);
select test_util.add_offering('fish_gone', 'fish', 3, 'lunch', now() - interval '1 second');

select test_util.login('admin1');
select lives_ok($q$ select public.admin_top_up(array[test_util.id('emp1'), test_util.id('emp2')], 100000, null, gen_random_uuid()) $q$, 'add balance');

select test_util.login('emp2');
select lives_ok($q$ select public.book_meals(array[test_util.id('rice_w2')], gen_random_uuid()) $q$, 'a colleague books the same meal');

select test_util.login('emp1');
select lives_ok($q$ select public.book_meals(array[
  test_util.id('rice_w1'), test_util.id('rice_w2'), test_util.id('rice_w3'), test_util.id('rice_w4'),
  test_util.id('rice_other_day'), test_util.id('rice_next_month'), test_util.id('fish_w1'), test_util.id('rice_dinner'),
  test_util.id('fish_a'), test_util.id('fish_b'), test_util.id('fish_c'), test_util.id('fish_gone')
], gen_random_uuid()) $q$, 'book the month');

-- 1000 x 6 + 2000 x 5 + 1000 (the same meal at dinner)
select is(test_util.balance('emp1'), '83000/17000', 'everything is held');

-- ---------------------------------------------------------------------------
-- Cancelling the series
-- ---------------------------------------------------------------------------

select test_util.login('emp2');
select throws_ok($q$ select public.cancel_booking_series(test_util.booking('emp1', 'rice_w1'), gen_random_uuid()) $q$,
  'P0001', 'booking_not_found', 'cannot cancel a colleague''s series');

select test_util.login('emp1');
select throws_ok($q$ select public.cancel_booking_series(test_util.booking('emp1', 'rice_w3'), gen_random_uuid()) $q$,
  'P0001', 'cancel_deadline_passed', 'the chosen meal must still be cancellable');
select is(test_util.balance('emp1'), '83000/17000', 'a refused series changes nothing');

select is((public.cancel_booking_series(test_util.booking('emp1', 'rice_w1'), test_util.id('series-key'))->>'cancelled')::integer, 3,
  'the same meal on the same weekday is cancelled');
select is(test_util.balance('emp1'), '86000/14000', 'three meals are refunded');
select is((public.cancel_booking_series(test_util.booking('emp1', 'rice_w1'), test_util.id('series-key'))->>'refunded')::bigint, 3000::bigint,
  'repeating the request returns the first answer');
select is(test_util.balance('emp1'), '86000/14000', 'a repeated request refunds once');

select is(test_util.status('emp1', 'rice_w1'), 'cancelled', 'first week cancelled');
select is(test_util.status('emp1', 'rice_w2'), 'cancelled', 'second week cancelled');
select is(test_util.status('emp1', 'rice_w4'), 'cancelled', 'fourth week cancelled');
select is(test_util.status('emp1', 'rice_w3'), 'booked', 'a meal past its deadline stays booked');
select is(test_util.status('emp1', 'rice_other_day'), 'booked', 'another weekday is untouched');
select is(test_util.status('emp1', 'rice_next_month'), 'booked', 'the next month is untouched');
select is(test_util.status('emp1', 'fish_w1'), 'booked', 'another meal is untouched');
select is(test_util.status('emp1', 'rice_dinner'), 'booked', 'the same meal at another period is untouched');
select is(test_util.status('emp2', 'rice_w2'), 'booked', 'a colleague''s booking is untouched');

select is((public.cancel_booking_series(test_util.booking('emp1', 'fish_b'), gen_random_uuid())->>'cancelled')::integer, 2,
  'a series starts from the chosen meal');
select is(test_util.status('emp1', 'fish_a'), 'booked', 'earlier weeks are not cancelled');
select is(test_util.status('emp1', 'fish_c'), 'cancelled', 'later weeks are cancelled');

select is((public.cancel_booking_series(test_util.booking('emp1', 'rice_other_day'), gen_random_uuid())->>'skipped')::integer, 0,
  'a meal with no repeats is a series of one');

select test_util.logout();
select is((select booked_count from public.meal_offerings where id = test_util.id('rice_w2')), 1, 'the seat counter is right');
select is((select count(*)::integer from public.pickup_tokens
           where booking_id = (select id from public.bookings where employee_id = test_util.id('emp1') and offering_id = test_util.id('rice_w2'))
             and revoked_at is null), 0, 'cancelled meals have no live code');
select is(private.check_wallet_integrity(), 0, 'wallets match their ledgers');

-- ---------------------------------------------------------------------------
-- Publishing a whole month
-- ---------------------------------------------------------------------------

select test_util.login('mgr1');
select lives_ok($q$
  insert into public.schedules (id, restaurant_id, meal_id, period, season, weekdays, start_date)
  values (test_util.id('soup-schedule'), test_util.id('rest'), test_util.id('soup'), 'dinner', 'normal', '{0,1,2,3,4,5,6}', current_date)
$q$, 'schedule a meal every day');
select lives_ok($q$ select public.publish_schedule() $q$, 'publish');

select test_util.logout();
select is((select max(service_date) from public.meal_offerings where meal_id = test_util.id('soup')),
  (test_util.base() + interval '1 month - 1 day')::date, 'meals are published through the end of next month');

-- ---------------------------------------------------------------------------
-- Edits reach meals nobody has booked
-- ---------------------------------------------------------------------------

create function test_util.soup(p_day integer) returns public.meal_offerings
language sql stable security definer set search_path = public as $$
  select * from public.meal_offerings where meal_id = test_util.id('soup') and service_date = test_util.base() + p_day;
$$;

select test_util.login('emp1');
select lives_ok($q$ select public.book_meals(array[(test_util.soup(5)).id], gen_random_uuid()) $q$, 'book one soup');

select test_util.login('mgr1');
select lives_ok($q$ update public.meals set price = 900 where id = test_util.id('soup') $q$, 'the manager changes the price');
select is((test_util.soup(6)).price, 900::bigint, 'an unbooked meal follows the new price');
select is((test_util.soup(5)).price, 500::bigint, 'a booked meal keeps the agreed price');

select lives_ok($q$
  update public.schedules
  set weekdays = array[extract(dow from test_util.base())::smallint]
  where id = test_util.id('soup-schedule')
$q$, 'the manager keeps only one weekday');
select is((test_util.soup(0)).status::text, 'open', 'that weekday stays open');
select is((test_util.soup(1)).status::text, 'cancelled', 'other weekdays with no bookings are withdrawn');
select is((test_util.soup(1)).cancel_reason, 'schedule_changed', 'the reason is recorded');
select is((test_util.soup(5)).status::text, 'open', 'a booked meal stays open');

select test_util.login('emp2');
select throws_ok($q$ select public.book_meals(array[(test_util.soup(1)).id], gen_random_uuid()) $q$,
  'P0001', 'offering_cancelled', 'a withdrawn meal cannot be booked');

select test_util.login('mgr1');
select lives_ok($q$ update public.schedules set weekdays = '{0,1,2,3,4,5,6}' where id = test_util.id('soup-schedule') $q$, 'the manager restores every weekday');
select is((test_util.soup(1)).status::text, 'open', 'withdrawn meals come back');
select is((test_util.soup(1)).price, 900::bigint, 'they come back at the current price');
select is((test_util.soup(1)).cancel_reason, null, 'the reason is cleared');

select lives_ok($q$ select public.cancel_offering((test_util.soup(2)).id, 'kitchen closed', gen_random_uuid()) $q$, 'the manager cancels one day by hand');
select lives_ok($q$ update public.meals set price = 950 where id = test_util.id('soup') $q$, 'another price change');
select is((test_util.soup(2)).status::text, 'cancelled', 'a meal cancelled by hand does not come back');

select lives_ok($q$ update public.meals set is_active = false where id = test_util.id('soup') $q$, 'the manager stops the meal');
select is((test_util.soup(3)).status::text, 'cancelled', 'an unbooked meal is withdrawn');
select is((test_util.soup(5)).status::text, 'open', 'a booked meal is still honoured');
select lives_ok($q$ update public.meals set is_active = true where id = test_util.id('soup') $q$, 'the manager brings it back');
select is((test_util.soup(3)).status::text, 'open', 'the meal returns');

select test_util.login('emp1');
-- 83000 + 3000 + 4000 + 1000 refunded, less the soup at the price it was booked for.
select is(test_util.balance('emp1'), '90500/9500', 'the booked price is what stays charged');

select test_util.logout();
select is(private.check_wallet_integrity(), 0, 'wallets still match their ledgers');

select * from finish();
rollback;
