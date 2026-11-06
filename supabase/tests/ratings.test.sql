-- Meal ratings: when they open and close, who can rate, and who can read them.

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

-- Marks a booking collected at a given time, as a scan would.
create function test_util.collect(p_booking text, p_at timestamptz) returns void
language sql as $$
  update public.bookings
  set status = 'picked_up', picked_up_at = p_at, picked_up_by = employee_id, pickup_method = 'scan', settled_at = p_at
  where id = test_util.id(p_booking);
$$;

create function test_util.window_of(p_booking text) returns text
language sql stable as $$
  select round(extract(epoch from rate_from - now()) / 60) || '/' || round(extract(epoch from rate_until - now()) / 60)
  from public.bookings where id = test_util.id(p_booking);
$$;

create function test_util.open_rating(p_booking text) returns void
language sql as $$
  update public.bookings set rate_from = now() - interval '1 minute', rate_until = now() + interval '1 hour'
  where id = test_util.id(p_booking);
$$;

insert into public.sites (id, name) values (test_util.id('site'), 'Site'), (test_util.id('site2'), 'Other site');
insert into public.restaurants (id, site_id, name, timezone) values
  (test_util.id('rest'), test_util.id('site'), 'Restaurant', 'Asia/Baghdad'),
  (test_util.id('rest2'), test_util.id('site2'), 'Other restaurant', 'Asia/Baghdad');

insert into auth.users (id, email)
  select test_util.id(name), name || '@meals.invalid'
  from unnest(array['admin', 'mgr1', 'mgr2', 'emp1', 'emp2', 'emp3', 'emp4']) as name;
insert into public.profiles (id, username, full_name, role, site_id, restaurant_id) values
  (test_util.id('admin'), 'admin', 'Admin', 'admin', null, null),
  (test_util.id('mgr1'), 'mgr1', 'Manager One', 'manager', test_util.id('site'), test_util.id('rest')),
  (test_util.id('mgr2'), 'mgr2', 'Manager Two', 'manager', test_util.id('site2'), test_util.id('rest2')),
  (test_util.id('emp1'), 'emp1', 'Sara Ali', 'employee', test_util.id('site'), test_util.id('rest')),
  (test_util.id('emp2'), 'emp2', 'emp2', 'employee', test_util.id('site'), test_util.id('rest')),
  (test_util.id('emp3'), 'emp3', 'emp3', 'employee', test_util.id('site'), test_util.id('rest')),
  (test_util.id('emp4'), 'emp4', 'emp4', 'employee', test_util.id('site'), test_util.id('rest'));

insert into public.meals (id, restaurant_id, name, price) values
  (test_util.id('rice'), test_util.id('rest'), 'Rice', 5000),
  (test_util.id('soup'), test_util.id('rest'), 'Soup', 3000);

-- Lunch is being collected now, dinner starts in five hours, breakfast tomorrow in thirty.
insert into public.meal_offerings (
  id, meal_id, restaurant_id, service_date, period, season, price,
  book_until, cancel_until, pickup_from, pickup_until
) values
  (test_util.id('lunch'), test_util.id('rice'), test_util.id('rest'), current_date, 'lunch', 'normal', 5000,
   now() - interval '3 hours', now() - interval '3 hours', now() - interval '1 hour', now() + interval '1 hour'),
  (test_util.id('dinner'), test_util.id('soup'), test_util.id('rest'), current_date, 'dinner', 'normal', 3000,
   now() + interval '1 hour', now() + interval '1 hour', now() + interval '5 hours', now() + interval '7 hours'),
  (test_util.id('breakfast'), test_util.id('soup'), test_util.id('rest'), current_date + 1, 'breakfast', 'normal', 3000,
   now() + interval '20 hours', now() + interval '20 hours', now() + interval '30 hours', now() + interval '32 hours');

insert into public.bookings (id, employee_id, offering_id, restaurant_id, amount) values
  (test_util.id('b1'), test_util.id('emp1'), test_util.id('lunch'), test_util.id('rest'), 5000),
  (test_util.id('b2'), test_util.id('emp2'), test_util.id('lunch'), test_util.id('rest'), 5000),
  (test_util.id('b3'), test_util.id('emp3'), test_util.id('lunch'), test_util.id('rest'), 5000),
  (test_util.id('b4'), test_util.id('emp4'), test_util.id('lunch'), test_util.id('rest'), 5000),
  (test_util.id('b5'), test_util.id('emp1'), test_util.id('dinner'), test_util.id('rest'), 3000);

-- ---------------------------------------------------------------------------
-- When rating opens and closes
-- ---------------------------------------------------------------------------

select test_util.collect('b1', now());
select is(test_util.window_of('b1'), '60/300', 'opens an hour after pickup and closes when dinner pickup starts');

select test_util.collect('b2', now() + interval '270 minutes');
select is(test_util.window_of('b2'), '330/450', 'stays open at least two hours when the next meal starts soon after');

select test_util.collect('b3', now() + interval '6 hours');
select is(test_util.window_of('b3'), '420/1800', 'after the last meal of the day it lasts until breakfast');

select test_util.collect('b4', now() + interval '31 hours');
select is(test_util.window_of('b4'), '1920/3360', 'with no next meal it closes after a day');

select is((select rate_from from public.bookings where id = test_util.id('b5')), null, 'a meal not yet collected has no rating time');

-- ---------------------------------------------------------------------------
-- Rating
-- ---------------------------------------------------------------------------

select test_util.login('emp1');
select is((select count(*)::integer from public.my_ratable_meals()), 0, 'nothing to rate in the first hour');
select throws_ok(format($$ select rate_meal(%L, 5, '{}', null, gen_random_uuid()) $$, test_util.id('b1')),
  'P0001', 'rating_not_open', 'rating in the first hour is refused');

select test_util.logout();
select test_util.open_rating('b1');
select test_util.login('emp1');

select is((select array_agg(meal_name) from public.my_ratable_meals()), array['Rice'], 'an hour later the meal waits for a rating');

select throws_ok(format($$ select rate_meal(%L, 0, '{}', null, gen_random_uuid()) $$, test_util.id('b1')),
  'P0001', 'invalid_stars', 'stars must be one to five');
select throws_ok(format($$ select rate_meal(%L, 4, array['bad_word'], null, gen_random_uuid()) $$, test_util.id('b1')),
  'P0001', 'invalid_tags', 'only the offered tags are accepted');
select throws_ok(format($$ select rate_meal(%L, 4, '{}', %L, gen_random_uuid()) $$, test_util.id('b1'), repeat('a', 501)),
  'P0001', 'comment_too_long', 'a comment is at most 500 characters');
select throws_ok(format($$ select rate_meal(%L, 4, '{}', null, gen_random_uuid()) $$, test_util.id('b5')),
  'P0001', 'not_ratable', 'a meal not collected cannot be rated');
select throws_ok($$ insert into public.meal_ratings (booking_id, employee_id, restaurant_id, meal_id, stars)
  values (md5('b1')::uuid, md5('emp1')::uuid, md5('rest')::uuid, md5('rice')::uuid, 5) $$,
  '42501', null, 'the app cannot write a rating directly');

select test_util.login('emp2');
select throws_ok(format($$ select rate_meal(%L, 1, '{}', null, gen_random_uuid()) $$, test_util.id('b1')),
  'P0001', 'booking_not_found', 'nobody can rate another person''s meal');

select test_util.login('emp1');
select lives_ok(format($$ select rate_meal(%L, 2, array['cold', 'small_portion'], '  The rice was cold  ', %L) $$,
  test_util.id('b1'), test_util.id('rate-key')), 'the owner rates the meal');
select is((select comment from public.meal_ratings where booking_id = test_util.id('b1')), 'The rice was cold', 'the comment is saved trimmed');
select lives_ok(format($$ select rate_meal(%L, 2, '{}', null, %L) $$, test_util.id('b1'), test_util.id('rate-key')),
  'a network retry of the same rating succeeds');
select throws_ok(format($$ select rate_meal(%L, 5, '{}', null, gen_random_uuid()) $$, test_util.id('b1')),
  'P0001', 'already_rated', 'a rating cannot be changed or sent twice');
select is((select count(*)::integer from public.meal_ratings), 1, 'one rating was saved');
select is((select count(*)::integer from public.my_ratable_meals()), 0, 'a rated meal no longer waits');

select test_util.logout();
update public.bookings set rate_from = now() - interval '3 hours', rate_until = now() - interval '1 second'
where id = test_util.id('b2');
select test_util.login('emp2');
select throws_ok(format($$ select rate_meal(%L, 5, '{}', null, gen_random_uuid()) $$, test_util.id('b2')),
  'P0001', 'rating_closed', 'rating after it closes is refused');
select is((select count(*)::integer from public.meal_ratings), 0, 'another employee cannot read the rating');

-- ---------------------------------------------------------------------------
-- Who reads ratings
-- ---------------------------------------------------------------------------

select test_util.login('mgr1');
select is(
  (select employee_name || ' ' || stars || ' ' || meal_name from public.meal_ratings_between(now() - interval '1 day', now() + interval '1 day')),
  'Sara Ali 2 Rice', 'the restaurant manager sees the rating with the employee''s name');

select test_util.login('mgr2');
select is((select count(*)::integer from public.meal_ratings_between(now() - interval '1 day', now() + interval '1 day')), 0,
  'another restaurant''s manager sees nothing');
select is((select count(*)::integer from public.meal_ratings), 0, 'nor through the table');

select test_util.login('admin');
select is((select restaurant_name from public.meal_ratings_between(now() - interval '1 day', now() + interval '1 day')),
  'Restaurant', 'the admin sees every restaurant''s ratings');

select test_util.login('emp1');
select throws_ok($$ select * from public.meal_ratings_between(now() - interval '1 day', now() + interval '1 day') $$,
  'P0001', 'forbidden', 'employees cannot list ratings');

select * from finish();
rollback;
