-- Several colleagues can collect one employee's meals; a meal collected by any of them
-- shows as collected to all, and no other code works after that, a screenshot included.

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

create function test_util.booking(p_owner text, p_offering text) returns uuid
language sql stable security definer as $$
  select id from public.bookings
  where employee_id = test_util.id(p_owner) and offering_id = test_util.id(p_offering)
    and status not in ('cancelled', 'cancelled_by_restaurant');
$$;

-- The latest code a holder was given for an owner's meal, revoked or not.
create function test_util.token(p_owner text, p_offering text, p_holder text) returns text
language sql stable security definer as $$
  select token from public.pickup_tokens
  where booking_id = test_util.booking(p_owner, p_offering) and holder_id = test_util.id(p_holder)
  order by created_at desc limit 1;
$$;

create function test_util.live_codes(p_owner text, p_offering text) returns integer
language sql stable security definer as $$
  select count(*)::integer from public.pickup_tokens
  where booking_id = test_util.booking(p_owner, p_offering) and revoked_at is null;
$$;

create function test_util.delegate(p_username text) returns jsonb
language sql as $$ select public.set_delegation(p_username, null, gen_random_uuid()); $$;

grant execute on all functions in schema test_util to public;

insert into public.sites (id, name) values (test_util.id('site'), 'Site');
insert into public.restaurants (id, site_id, name, timezone) values
  (test_util.id('rest'), test_util.id('site'), 'Restaurant', 'Asia/Baghdad');

insert into auth.users (id, email)
  select test_util.id(name), name || '@meals.invalid'
  from unnest(array['admin', 'mgr', 'emp1', 'emp2', 'emp3', 'emp4', 'emp5', 'emp6', 'emp7']) as name;
insert into public.profiles (id, username, full_name, role, site_id, restaurant_id)
  select test_util.id(name), name, 'Name ' || name, role::public.user_role,
         case when role = 'admin' then null else test_util.id('site') end,
         case when role = 'admin' then null else test_util.id('rest') end
  from (values ('admin', 'admin'), ('mgr', 'manager'), ('emp1', 'employee'), ('emp2', 'employee'),
               ('emp3', 'employee'), ('emp4', 'employee'), ('emp5', 'employee'), ('emp6', 'employee'),
               ('emp7', 'employee')) as v(name, role);

insert into public.meals (id, restaurant_id, name, price) values
  (test_util.id('rice'), test_util.id('rest'), 'Rice', 5000);
insert into public.meal_offerings (
  id, meal_id, restaurant_id, service_date, period, season, price,
  book_until, cancel_until, pickup_from, pickup_until
) values
  (test_util.id('lunch'), test_util.id('rice'), test_util.id('rest'), current_date + 1, 'lunch', 'normal', 5000,
   now() + interval '1 hour', now() + interval '1 hour', now() + interval '2 hours', now() + interval '3 hours');

select test_util.login('admin');
select lives_ok($q$ select public.admin_top_up(array[test_util.id('emp1')], 20000, null, gen_random_uuid()) $q$, 'balance for emp1');

-- ---------------------------------------------------------------------------
-- Choosing several colleagues
-- ---------------------------------------------------------------------------

select test_util.login('emp1');
select lives_ok($q$ select test_util.delegate('emp2') $q$, 'choose a first colleague');
select lives_ok($q$ select test_util.delegate('emp3') $q$, 'and a second one, keeping the first');
select is((select array_agg(username order by username) from public.my_delegates()), array['emp2', 'emp3'],
  'both can collect');
select is(test_util.delegate('EMP2 ')->>'delegation_id',
  (select delegation_id::text from public.my_delegates() where username = 'emp2'),
  'choosing the same colleague again changes nothing');
select is((select count(*)::integer from public.my_delegates()), 2, 'still two');
select is((select full_name from public.my_delegates() where username = 'emp3'), 'Name emp3', 'the list shows names');

select lives_ok($q$ select test_util.delegate('emp4') $q$, 'a third');
select lives_ok($q$ select test_util.delegate('emp5') $q$, 'a fourth');
select lives_ok($q$ select test_util.delegate('emp6') $q$, 'a fifth');
select throws_ok($q$ select test_util.delegate('emp7') $q$, 'P0001', 'too_many_delegates', 'not a sixth');

select test_util.login('emp2');
select is((select count(*)::integer from public.my_delegates()), 0, 'a delegate does not see the owner''s list as theirs');
select test_util.login('mgr');
select is((select count(*)::integer from public.my_delegates()), 0, 'a manager gets no list');

-- ---------------------------------------------------------------------------
-- Every colleague gets a code; withdrawing one cancels only theirs
-- ---------------------------------------------------------------------------

select test_util.login('emp1');
select lives_ok($q$ select public.book_meals(array[test_util.id('lunch')], gen_random_uuid()) $q$, 'book lunch');
select is(test_util.live_codes('emp1', 'lunch'), 6, 'one code for the owner and one for each of the five');

select lives_ok($q$ select public.revoke_delegation((select delegation_id from public.my_delegates() where username = 'emp6')) $q$,
  'withdraw the fifth');
select is((select count(*)::integer from public.my_delegates()), 4, 'four left');
select is(test_util.live_codes('emp1', 'lunch'), 5, 'the withdrawn colleague''s code is cancelled');
select lives_ok($q$ select test_util.delegate('emp7') $q$, 'room again for another');
select is(test_util.live_codes('emp1', 'lunch'), 6, 'who gets a code for the meal already booked');

-- ---------------------------------------------------------------------------
-- Collected by one, shown as collected to all
-- ---------------------------------------------------------------------------

select test_util.logout();
update public.meal_offerings
set book_until = now() - interval '3 hours', cancel_until = now() - interval '3 hours',
    pickup_from = now() - interval '1 hour', pickup_until = now() + interval '1 hour'
where id = test_util.id('lunch');

select test_util.login('emp2');
select isnt((select token from public.my_pickups() where booking_id = test_util.booking('emp1', 'lunch')), null,
  'a colleague sees the code once pickup starts');

select test_util.login('mgr');
select is(public.redeem_pickup(test_util.token('emp1', 'lunch', 'emp3'), gen_random_uuid())->>'ok', 'true',
  'one colleague collects');
select is(public.redeem_pickup(test_util.token('emp1', 'lunch', 'emp2'), gen_random_uuid())->>'reason', 'already_picked_up',
  'a second colleague''s code is refused');
select is(public.redeem_pickup(test_util.token('emp1', 'lunch', 'emp1'), gen_random_uuid())->>'reason', 'already_picked_up',
  'and so is the owner''s, even from a screenshot');
select is(test_util.live_codes('emp1', 'lunch'), 0, 'no code is left alive');

select test_util.login('emp2');
select is((select token from public.my_pickups() where booking_id = test_util.booking('emp1', 'lunch')), null,
  'the other colleague no longer gets the code');
select is((select picked_up_by_name from public.my_pickups() where booking_id = test_util.booking('emp1', 'lunch')), 'Name emp3',
  'but sees who collected it');
select isnt((select picked_up_at from public.my_pickups() where booking_id = test_util.booking('emp1', 'lunch')), null,
  'and when');

select test_util.login('emp1');
select is((select picked_up_by_name from public.my_pickups() where booking_id = test_util.booking('emp1', 'lunch')), 'Name emp3',
  'the owner sees it too');
select is((select count(*)::integer from public.my_pickups()), 1, 'once, not once per code');

select test_util.login('emp6');
select is((select count(*)::integer from public.my_pickups()), 0, 'a colleague withdrawn earlier sees nothing');

select * from finish();
rollback;
