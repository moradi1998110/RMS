-- The whole path a meal takes, using the same calls as the app: a manager adds and
-- schedules meals, and employees see and book them on the coming days.

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

-- Days far enough ahead that no deadline depends on when these tests run.
create function test_util.day(p_offset integer) returns date
language sql stable as $$ select (now() at time zone 'Asia/Baghdad')::date + 2 + p_offset; $$;

create function test_util.dow(p_offset integer) returns smallint
language sql stable as $$ select extract(dow from test_util.day(p_offset))::smallint; $$;

create function test_util.end_of_next_month() returns date
language sql stable as $$
  select (date_trunc('month', now() at time zone 'Asia/Baghdad') + interval '2 months - 1 day')::date;
$$;

-- As the signed-in user, so row security applies just as it does in the app.
create function test_util.visible(p_meal text, p_day date, p_period public.meal_period default 'dinner') returns uuid
language sql stable as $$
  select id from public.meal_offerings
  where meal_id = test_util.id(p_meal) and service_date = p_day and period = p_period and status = 'open';
$$;

-- Ignores row security, for a user trying to reach a meal they cannot see.
create function test_util.any_offering(p_meal text, p_day date) returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.meal_offerings where meal_id = test_util.id(p_meal) and service_date = p_day;
$$;

create function test_util.key() returns uuid
language sql volatile as $$ select gen_random_uuid(); $$;

create function test_util.available(p_name text) returns bigint
language sql security definer set search_path = public as $$
  select available from public.wallets where employee_id = test_util.id(p_name);
$$;

insert into public.sites (id, name) values (test_util.id('site'), 'Site'), (test_util.id('site2'), 'Other site');
insert into public.restaurants (id, site_id, name, timezone) values
  (test_util.id('rest'), test_util.id('site'), 'Restaurant', 'Asia/Baghdad'),
  (test_util.id('rest2'), test_util.id('site2'), 'Other restaurant', 'Asia/Baghdad');

insert into auth.users (id, email)
  select test_util.id(name), name || '@meals.invalid' from unnest(array['mgr1', 'emp1', 'emp2', 'stranger']) as name;
insert into public.profiles (id, username, full_name, role, site_id, restaurant_id) values
  (test_util.id('mgr1'), 'mgr1', 'mgr1', 'manager', test_util.id('site'), test_util.id('rest')),
  (test_util.id('emp1'), 'emp1', 'emp1', 'employee', test_util.id('site'), test_util.id('rest')),
  (test_util.id('emp2'), 'emp2', 'emp2', 'employee', test_util.id('site'), test_util.id('rest')),
  (test_util.id('stranger'), 'stranger', 'stranger', 'employee', test_util.id('site2'), test_util.id('rest2'));
select private.post_tx(test_util.id('emp1'), 'topup', 500000, 0);
select private.post_tx(test_util.id('emp2'), 'topup', 500000, 0);
select private.post_tx(test_util.id('stranger'), 'topup', 500000, 0);

-- A meal with no schedule is not on offer.
select test_util.login('mgr1');
insert into public.meals (id, restaurant_id, name, price) values
  (test_util.id('burger'), test_util.id('rest'), 'Burger', 5000),
  (test_util.id('soup'), test_util.id('rest'), 'Soup', 2000),
  (test_util.id('unscheduled'), test_util.id('rest'), 'Unscheduled', 1000);

select is(
  (select count(*)::integer from public.meal_offerings where meal_id = test_util.id('unscheduled')),
  0, 'a meal not yet in the program has no days to book');

-- A weekly schedule covers that weekday through the end of next month.
insert into public.schedules (id, restaurant_id, meal_id, period, season, weekdays, repeat_type, start_date)
values (test_util.id('burger_sched'), test_util.id('rest'), test_util.id('burger'), 'dinner', 'normal',
        array[test_util.dow(0)], 'weekly', test_util.day(-2));
select lives_ok($$ select publish_schedule() $$, 'publishing works for the manager');

select is(
  (select array_agg(service_date order by service_date) from public.meal_offerings
   where meal_id = test_util.id('burger') and service_date >= test_util.day(0)),
  (select array_agg(d::date order by d) from generate_series(test_util.day(0), test_util.end_of_next_month(), interval '7 days') as d),
  'every matching weekday is offered, none skipped');

select is(
  (select count(*)::integer from public.meal_offerings where meal_id = test_util.id('burger') and status <> 'open'),
  0, 'all of them are open');

select ok(
  (select bool_and(book_until > now()) from public.meal_offerings where meal_id = test_util.id('burger') and service_date >= test_util.day(0)),
  'and all are still inside their booking time');

-- The employee sees and books the coming week, a later week and the very last one.
select test_util.login('emp1');

select isnt(test_util.visible('burger', test_util.day(0)), null, 'the employee sees the nearest day');
select isnt(test_util.visible('burger', test_util.day(7)), null, 'and next week');

select lives_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.visible('burger', test_util.day(0)), test_util.key()), 'books the nearest day');
select lives_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.visible('burger', test_util.day(7)), test_util.key()), 'books next week');

select lives_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$,
  (select id from public.meal_offerings where meal_id = test_util.id('burger') and status = 'open' order by service_date desc limit 1),
  test_util.key()), 'books the last published day');

select is(test_util.available('emp1'), 485000::bigint, 'three meals held, charged once each');

-- A cancelled meal can be booked again.
select lives_ok(format($$ select cancel_booking((select id from public.bookings where offering_id = %L and status = 'booked' limit 1), %L) $$,
  test_util.visible('burger', test_util.day(7)), test_util.key()), 'cancels next week');
select is(test_util.available('emp1'), 490000::bigint, 'and the money comes back');
select lives_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.visible('burger', test_util.day(7)), test_util.key()), 'books it again after cancelling');
select throws_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.visible('burger', test_util.day(7)), test_util.key()),
  'P0001', 'already_booked', 'but not twice');

-- Another employee is free to book the same meal.
select test_util.login('emp2');
select lives_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.visible('burger', test_util.day(0)), test_util.key()), 'a colleague books the same day');

-- Another restaurant sees none of this and cannot book it.
select test_util.login('stranger');
select is(test_util.visible('burger', test_util.day(14)), null, 'an employee of another restaurant does not see it');
select throws_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.any_offering('burger', test_util.day(14)), test_util.key()),
  'P0001', 'wrong_restaurant', 'and cannot book it');

-- The manager adds a second meal to the same period and day.
select test_util.login('mgr1');
insert into public.schedules (id, restaurant_id, meal_id, period, season, weekdays, repeat_type, start_date)
values (test_util.id('soup_sched'), test_util.id('rest'), test_util.id('soup'), 'dinner', 'normal',
        array[test_util.dow(0)], 'weekly', test_util.day(-2));
select publish_schedule();

select test_util.login('emp1');
select lives_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.visible('soup', test_util.day(0)), test_util.key()), 'a second meal on that day can be booked too');

-- The manager adds another weekday to an existing schedule, as the app does.
select test_util.login('mgr1');
update public.schedules set weekdays = array[test_util.dow(0), test_util.dow(1)] where id = test_util.id('burger_sched');
select publish_schedule();

select test_util.login('emp1');
select isnt(test_util.visible('burger', test_util.day(1)), null, 'the added weekday appears');
select isnt(test_util.visible('burger', test_util.day(14)), null, 'unbooked days on the old weekday return');
select lives_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.visible('burger', test_util.day(8)), test_util.key()), 'and the added weekday can be booked');
select isnt(test_util.visible('burger', test_util.day(0)), null, 'booked days stay');

-- The manager removes that weekday again.
select test_util.login('mgr1');
update public.schedules set weekdays = array[test_util.dow(0)] where id = test_util.id('burger_sched');

select test_util.login('emp1');
select is(test_util.visible('burger', test_util.day(1)), null, 'an unbooked removed day disappears');
select isnt(test_util.visible('burger', test_util.day(8)), null, 'a booked removed day stays for whoever holds it');

-- "This week only" stops after seven days.
select test_util.login('mgr1');
insert into public.meals (id, restaurant_id, name, price) values (test_util.id('once'), test_util.id('rest'), 'Once', 1000);
insert into public.schedules (restaurant_id, meal_id, period, season, weekdays, repeat_type, start_date, end_date)
values (test_util.id('rest'), test_util.id('once'), 'lunch', 'normal', array[test_util.dow(0)], 'one_week', test_util.day(-2), test_util.day(4));
select publish_schedule();
select is(
  (select array_agg(service_date) from public.meal_offerings where meal_id = test_util.id('once')),
  array[test_util.day(0)], 'a week-only schedule gives that week only');

-- A price change reaches unbooked days, and never one already booked.
update public.meals set price = 6000 where id = test_util.id('burger');
select is(
  (select price from public.meal_offerings where id = test_util.visible('burger', test_util.day(14))),
  6000::bigint, 'a new price reaches unbooked days');
select is(
  (select price from public.meal_offerings where id = test_util.visible('burger', test_util.day(0))),
  5000::bigint, 'a booked day keeps its price');

-- Stopping a meal hides its unbooked days.
update public.meals set is_active = false where id = test_util.id('soup');
select is(test_util.visible('soup', test_util.day(7)), null, 'a stopped meal leaves the program');
select isnt(test_util.visible('soup', test_util.day(0)), null, 'but a booked day stays');

-- Booking times come from the server clock, whatever the phone shows.
select test_util.logout();
update public.meal_offerings set book_until = now() - interval '1 second'
where meal_id = test_util.id('burger') and service_date = test_util.day(14);

select test_util.login('emp2');
select throws_ok(format($$ select book_meals(array[%L]::uuid[], %L) $$, test_util.visible('burger', test_util.day(14)), test_util.key()),
  'P0001', 'booking_closed', 'booking after the deadline is refused');

select * from finish();
rollback;
