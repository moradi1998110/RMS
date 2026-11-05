-- Breakfast, lunch and dinner each follow their own cancellation rule.

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

-- The wall-clock moment for "day offset + time" around a date, in the restaurant's zone.
create function test_util.local_at(p_days integer, p_time time) returns timestamptz
language sql stable as $$
  select ((current_date + p_days) + p_time) at time zone 'Asia/Baghdad';
$$;

create function test_util.cancel_until(p_meal text, p_days integer) returns timestamptz
language sql security definer set search_path = public as $$
  select cancel_until from public.meal_offerings
  where meal_id = test_util.id(p_meal) and service_date = current_date + p_days;
$$;

create function test_util.offering(p_meal text, p_days integer) returns uuid
language sql security definer set search_path = public as $$
  select id from public.meal_offerings
  where meal_id = test_util.id(p_meal) and service_date = current_date + p_days;
$$;

create function test_util.booking(p_meal text, p_days integer) returns uuid
language sql security definer set search_path = public as $$
  select id from public.bookings where offering_id = test_util.offering(p_meal, p_days);
$$;

insert into public.sites (id, name) values (test_util.id('site'), 'Site');
insert into public.restaurants (id, site_id, name, timezone)
  values (test_util.id('rest'), test_util.id('site'), 'Restaurant', 'Asia/Baghdad');

insert into auth.users (id, email)
  select test_util.id(name), name || '@meals.invalid' from unnest(array['admin1', 'mgr1', 'emp1']) as name;
insert into public.profiles (id, username, full_name, role) values (test_util.id('admin1'), 'admin1', 'admin1', 'admin');
insert into public.profiles (id, username, full_name, role, site_id, restaurant_id) values
  (test_util.id('mgr1'), 'mgr1', 'mgr1', 'manager', test_util.id('site'), test_util.id('rest')),
  (test_util.id('emp1'), 'emp1', 'emp1', 'employee', test_util.id('site'), test_util.id('rest'));

insert into public.meals (id, restaurant_id, name, price) values
  (test_util.id('breakfast'), test_util.id('rest'), 'Eggs', 1000),
  (test_util.id('lunch'), test_util.id('rest'), 'Rice', 1000),
  (test_util.id('dinner'), test_util.id('rest'), 'Soup', 1000),
  (test_util.id('late_dinner'), test_util.id('rest'), 'Grill', 1000);

select is((select count(*)::integer from public.time_defaults where restaurant_id = test_util.id('rest')), 5,
  'a new restaurant has a rule for every meal period');

-- ---------------------------------------------------------------------------
-- Schedules follow their period's rule
-- ---------------------------------------------------------------------------

select test_util.login('mgr1');

select lives_ok($q$
  insert into public.schedules (restaurant_id, meal_id, period, season, weekdays, start_date) values
    (test_util.id('rest'), test_util.id('breakfast'), 'breakfast', 'normal', '{0,1,2,3,4,5,6}', current_date),
    (test_util.id('rest'), test_util.id('lunch'), 'lunch', 'normal', '{0,1,2,3,4,5,6}', current_date),
    (test_util.id('rest'), test_util.id('dinner'), 'dinner', 'normal', '{0,1,2,3,4,5,6}', current_date)
$q$, 'a manager schedules meals without typing any times');

select lives_ok($q$
  insert into public.schedules (
    restaurant_id, meal_id, period, season, weekdays, start_date,
    book_day_offset, book_time, cancel_day_offset, cancel_time,
    pickup_from_day_offset, pickup_from_time, pickup_until_day_offset, pickup_until_time
  ) values (
    test_util.id('rest'), test_util.id('late_dinner'), 'dinner', 'normal', '{0,1,2,3,4,5,6}', current_date,
    0, '12:00', 0, '15:00', 0, '19:00', 0, '21:00'
  )
$q$, 'a schedule can still set its own times');

select throws_ok($q$
  insert into public.schedules (restaurant_id, meal_id, period, season, weekdays, start_date, cancel_time)
  values (test_util.id('rest'), test_util.id('lunch'), 'lunch', 'normal', '{1}', current_date, '09:00')
$q$, '23514', null, 'a schedule cannot set only some of the times');

select lives_ok($q$ select public.publish_schedule() $q$, 'publish the schedule');

select is(test_util.cancel_until('breakfast', 3), test_util.local_at(3, '05:00'), 'breakfast: closes at 05:00 the same day');
select is((select book_until from public.meal_offerings where id = test_util.offering('breakfast', 3)), test_util.local_at(3, '05:00'), 'booking closes at the same hour');
select is(test_util.cancel_until('lunch', 3), test_util.local_at(3, '10:00'), 'lunch: closes at 10:00 the same day');
select is(test_util.cancel_until('dinner', 3), test_util.local_at(3, '16:00'), 'dinner: closes at 16:00 the same day');
select is(test_util.cancel_until('late_dinner', 3), test_util.local_at(3, '15:00'), 'a schedule with its own times keeps them');

-- ---------------------------------------------------------------------------
-- Each meal's deadline is enforced on its own
-- ---------------------------------------------------------------------------

select test_util.login('admin1');
select lives_ok($q$ select public.admin_top_up(array[test_util.id('emp1')], 20000, null, gen_random_uuid()) $q$, 'add balance');

select test_util.login('emp1');
select lives_ok($q$ select public.book_meals(
  array[test_util.offering('breakfast', 3), test_util.offering('lunch', 3), test_util.offering('dinner', 3),
        test_util.offering('breakfast', 4), test_util.offering('lunch', 4), test_util.offering('dinner', 4)],
  gen_random_uuid()) $q$, 'book all three meals on two days');

-- Move the clock point: breakfast has closed, lunch and dinner have not.
select test_util.logout();
update public.meal_offerings set cancel_until = now() - interval '1 second' where id = test_util.offering('breakfast', 3);

select test_util.login('emp1');
select throws_ok($q$ select public.cancel_booking(test_util.booking('breakfast', 3), gen_random_uuid()) $q$,
  'P0001', 'cancel_deadline_passed', 'breakfast can no longer be cancelled');
select lives_ok($q$ select public.cancel_booking(test_util.booking('lunch', 3), gen_random_uuid()) $q$,
  'lunch on the same day can still be cancelled');

select test_util.logout();
update public.meal_offerings set cancel_until = now() - interval '1 second' where id = test_util.offering('dinner', 3);

select test_util.login('emp1');
select throws_ok($q$ select public.cancel_booking(test_util.booking('dinner', 3), gen_random_uuid()) $q$,
  'P0001', 'cancel_deadline_passed', 'dinner can no longer be cancelled');

-- ---------------------------------------------------------------------------
-- The manager changes a rule
-- ---------------------------------------------------------------------------

select throws_ok($q$ select public.set_meal_times('lunch', -1, '20:00', 0, '09:00', 0, '12:00', 0, '14:30') $q$,
  'P0001', 'forbidden', 'an employee cannot change a rule');
select throws_ok($q$ update public.time_defaults set cancel_time = '11:00' $q$, '42501', null, 'rules cannot be changed directly');

select test_util.login('mgr1');
select throws_ok($q$ update public.time_defaults set cancel_time = '11:00' $q$, '42501', null, 'not even by a manager');
select throws_ok($q$ select public.set_meal_times('lunch', -1, '20:00', 0, '13:00', 0, '12:00', 0, '14:30') $q$,
  'P0001', 'invalid_times', 'cancel cannot close after pickup starts');

select lives_ok($q$ select public.set_meal_times('lunch', -1, '20:00', 0, '09:00', 0, '12:00', 0, '14:30') $q$, 'the manager moves lunch to 09:00');
select is(test_util.cancel_until('lunch', 3), test_util.local_at(3, '09:00'), 'a lunch with no bookings follows the new rule');
select is(test_util.cancel_until('lunch', 4), test_util.local_at(4, '10:00'), 'a booked lunch keeps the deadline already agreed');
select is(test_util.cancel_until('breakfast', 5), test_util.local_at(5, '05:00'), 'changing lunch does not touch breakfast');

select lives_ok($q$ select public.set_meal_times('dinner', 0, '12:00', 0, '13:00', 0, '18:00', 0, '20:30') $q$, 'the manager moves dinner to 13:00');
select is(test_util.cancel_until('dinner', 5), test_util.local_at(5, '13:00'), 'dinner follows the new rule');
select is(test_util.cancel_until('late_dinner', 5), test_util.local_at(5, '15:00'), 'a schedule with its own times is not changed');

select test_util.logout();
select is(private.check_wallet_integrity(), 0, 'wallets still match their ledgers');

select * from finish();
rollback;
