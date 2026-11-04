-- Database tests for wallet, booking, pickup, delegation and Ramadan rules.
-- Run with: supabase test db
-- Everything rolls back at the end. Simultaneous requests cannot be exercised from a
-- single transaction, so this file does not cover them.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- ---------------------------------------------------------------------------
-- Helpers and fixtures
-- ---------------------------------------------------------------------------

create schema test_util;
grant usage on schema test_util to public;

-- Readable fixture ids: test_util.id('emp1') is always the same uuid.
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

create function test_util.balance(p_name text) returns text
language sql security definer set search_path = public as $$
  select available || '/' || held from public.wallets where employee_id = test_util.id(p_name);
$$;

create function test_util.booking(p_employee text, p_offering text) returns uuid
language sql security definer set search_path = public as $$
  select id from public.bookings
  where employee_id = test_util.id(p_employee) and offering_id = test_util.id(p_offering)
  order by created_at desc, id limit 1;
$$;

create function test_util.status(p_employee text, p_offering text) returns text
language sql security definer set search_path = public as $$
  select status::text from public.bookings where id = test_util.booking(p_employee, p_offering);
$$;

create function test_util.token(p_employee text, p_offering text, p_holder text) returns text
language sql security definer set search_path = public as $$
  select token from public.pickup_tokens
  where booking_id = test_util.booking(p_employee, p_offering) and holder_id = test_util.id(p_holder)
  order by created_at desc, id limit 1;
$$;

create function test_util.short_code(p_employee text, p_offering text, p_holder text) returns text
language sql security definer set search_path = public as $$
  select short_code from public.pickup_tokens
  where booking_id = test_util.booking(p_employee, p_offering)
    and holder_id = test_util.id(p_holder) and revoked_at is null;
$$;

create function test_util.tx_count(p_employee text, p_offering text, p_type public.wallet_tx_type) returns integer
language sql security definer set search_path = public as $$
  select count(*)::integer from public.wallet_transactions
  where booking_id = test_util.booking(p_employee, p_offering) and type = p_type;
$$;

create function test_util.add_user(p_name text, p_username text, p_role public.user_role, p_site text, p_restaurant text)
returns void
language plpgsql as $$
begin
  insert into auth.users (id, email) values (test_util.id(p_name), p_username || '@meals.invalid');
  insert into public.profiles (id, username, full_name, role, site_id, restaurant_id)
  values (test_util.id(p_name), p_username, p_name, p_role, test_util.id(p_site), test_util.id(p_restaurant));
end;
$$;

create function test_util.add_offering(
  p_name text, p_meal text, p_price bigint, p_days integer, p_capacity integer default null,
  p_book_until timestamptz default now() + interval '1 day',
  p_cancel_until timestamptz default now() + interval '1 day'
) returns void
language sql as $$
  insert into public.meal_offerings (
    id, meal_id, restaurant_id, service_date, period, season, price,
    book_until, cancel_until, pickup_from, pickup_until, capacity
  )
  select test_util.id(p_name), m.id, m.restaurant_id, current_date + p_days,
         'lunch'::public.meal_period, 'normal'::public.season_type, p_price,
         p_book_until, p_cancel_until, now() + interval '2 days', now() + interval '3 days', p_capacity
  from public.meals m where m.id = test_util.id(p_meal);
$$;

create function test_util.open_pickup(p_offering text) returns void
language sql as $$
  update public.meal_offerings
  set book_until = now() - interval '3 hours', cancel_until = now() - interval '3 hours',
      pickup_from = now() - interval '1 hour', pickup_until = now() + interval '1 hour'
  where id = test_util.id(p_offering);
$$;

create function test_util.end_pickup(p_offering text) returns void
language sql as $$
  update public.meal_offerings
  set book_until = now() - interval '3 hours', cancel_until = now() - interval '3 hours',
      pickup_from = now() - interval '2 hours', pickup_until = now() - interval '1 hour'
  where id = test_util.id(p_offering);
$$;

insert into public.sites (id, name) values (test_util.id('site1'), 'Site 1'), (test_util.id('site2'), 'Site 2');
insert into public.restaurants (id, site_id, name, timezone) values
  (test_util.id('rest1'), test_util.id('site1'), 'Restaurant 1', 'Asia/Baghdad'),
  (test_util.id('rest2'), test_util.id('site2'), 'Restaurant 2', 'Asia/Baghdad');

insert into auth.users (id, email) values (test_util.id('admin'), 'admin1@meals.invalid');
insert into public.profiles (id, username, full_name, role)
values (test_util.id('admin'), 'admin1', 'admin', 'admin');

select test_util.add_user('mgr1', 'mgr1', 'manager', 'site1', 'rest1');
select test_util.add_user('mgr2', 'mgr2', 'manager', 'site2', 'rest2');
select test_util.add_user('emp1', 'emp1', 'employee', 'site1', 'rest1');
select test_util.add_user('emp2', 'emp2', 'employee', 'site1', 'rest1');
select test_util.add_user('emp3', 'emp3', 'employee', 'site1', 'rest1');
select test_util.add_user('emp4', 'emp4', 'employee', 'site2', 'rest2');

insert into public.meals (id, restaurant_id, name, price) values
  (test_util.id('meal1'), test_util.id('rest1'), 'Rice', 5000),
  (test_util.id('meal2'), test_util.id('rest1'), 'Fish', 7000),
  (test_util.id('mealr2'), test_util.id('rest2'), 'Kebab', 6000),
  (test_util.id('iftar2'), test_util.id('rest2'), 'Iftar', 8000);

select test_util.add_offering('o1', 'meal1', 5000, 20);
select test_util.add_offering('o2', 'meal2', 7000, 21);
select test_util.add_offering('closed', 'meal1', 5000, 22, null, now() - interval '1 second');
select test_util.add_offering('one_seat', 'meal1', 5000, 23, 1);
select test_util.add_offering('cancel_soon', 'meal1', 5000, 24, null, now() + interval '1 day', now() + interval '1 second');
select test_util.add_offering('cancel_gone', 'meal1', 5000, 25, null, now() + interval '1 day', now() - interval '1 second');
select test_util.add_offering('cancel_edge', 'meal1', 5000, 26, null, now() + interval '1 day', now());
select test_util.add_offering('standing', 'meal1', 5000, 27);
select test_util.add_offering('expiring', 'meal1', 5000, 28);
select test_util.add_offering('restaurant_cancels', 'meal1', 5000, 29);
select test_util.add_offering('rest2_meal', 'mealr2', 6000, 30);

-- ---------------------------------------------------------------------------
-- Credit
-- ---------------------------------------------------------------------------

select test_util.login('mgr1');
select throws_ok($q$ select public.admin_top_up(array[test_util.id('emp1')], 100, null, gen_random_uuid()) $q$,
  'P0001', 'forbidden', 'manager cannot add balance');

select test_util.login('emp1');
select throws_ok($q$ select public.admin_top_up(array[test_util.id('emp1')], 100, null, gen_random_uuid()) $q$,
  'P0001', 'forbidden', 'employee cannot add balance to themselves');

select test_util.login('admin');
select throws_ok($q$ select public.admin_top_up(array[test_util.id('emp1')], 0, null, gen_random_uuid()) $q$,
  'P0001', 'invalid_amount', 'zero top up is rejected');
select throws_ok($q$ select public.admin_top_up(array[test_util.id('mgr1')], 100, null, gen_random_uuid()) $q$,
  'P0001', 'invalid_employee', 'cannot top up a manager');

select lives_ok($q$ select public.admin_top_up(array[test_util.id('emp1'), test_util.id('emp2')], 20000, 'monthly', test_util.id('topup-key')) $q$,
  'admin tops up a group');
select lives_ok($q$ select public.admin_top_up(array[test_util.id('emp1'), test_util.id('emp2')], 20000, 'monthly', test_util.id('topup-key')) $q$,
  'repeating the same request succeeds');
select is(test_util.balance('emp1'), '20000/0', 'a repeated top up credits only once');
select is(test_util.balance('emp2'), '20000/0', 'each group member is credited');

select lives_ok($q$ select public.admin_top_up(array[test_util.id('emp3')], 1000, null, gen_random_uuid()) $q$, 'small balance for emp3');
select lives_ok($q$ select public.admin_top_up(array[test_util.id('emp4')], 20000, null, gen_random_uuid()) $q$, 'balance for emp4');

select throws_ok($q$ select public.admin_adjust(test_util.id('emp3'), -500, ' ', gen_random_uuid()) $q$,
  'P0001', 'reason_required', 'an adjustment needs a written reason');
select throws_ok($q$ select public.admin_adjust(test_util.id('emp3'), -5000, 'fix', gen_random_uuid()) $q$,
  'P0001', 'insufficient_balance', 'an adjustment cannot make a balance negative');

-- ---------------------------------------------------------------------------
-- Booking
-- ---------------------------------------------------------------------------

select test_util.login('emp3');
select throws_ok($q$ select public.book_meals(array[test_util.id('o1')], gen_random_uuid()) $q$,
  'P0001', 'insufficient_balance', 'cannot book without enough balance');
select is(test_util.balance('emp3'), '1000/0', 'a failed booking deducts nothing');

select test_util.login('emp1');
select throws_ok($q$ select public.book_meals(array[test_util.id('o1'), test_util.id('closed')], gen_random_uuid()) $q$,
  'P0001', 'booking_closed', 'a closed meal rejects the whole selection');
select is(test_util.balance('emp1'), '20000/0', 'nothing is deducted when one item fails');
select is(test_util.status('emp1', 'o1'), null, 'no partial booking is left behind');

select throws_ok($q$ select public.book_meals(array[]::uuid[], gen_random_uuid()) $q$,
  'P0001', 'empty_selection', 'an empty selection is rejected');
select throws_ok($q$ select public.book_meals(array[gen_random_uuid()], gen_random_uuid()) $q$,
  'P0001', 'offering_not_found', 'an unknown meal is rejected');
select throws_ok($q$ select public.book_meals(array[test_util.id('rest2_meal')], gen_random_uuid()) $q$,
  'P0001', 'wrong_restaurant', 'cannot book from another restaurant');

select is((public.book_meals(array[test_util.id('o1'), test_util.id('o2')], test_util.id('book-key'))->>'total')::bigint, 12000::bigint,
  'several meals are booked together');
select is(test_util.balance('emp1'), '8000/12000', 'the amount moves from available to held');
select is((public.book_meals(array[test_util.id('o1'), test_util.id('o2')], test_util.id('book-key'))->>'total')::bigint, 12000::bigint,
  'repeating the request returns the first answer');
select is(test_util.balance('emp1'), '8000/12000', 'a repeated booking deducts once');

select throws_ok($q$ select public.book_meals(array[test_util.id('o1')], gen_random_uuid()) $q$,
  'P0001', 'already_booked', 'cannot book the same meal twice');

select test_util.login('mgr1');
select throws_ok($q$ select public.book_meals(array[test_util.id('o1')], gen_random_uuid()) $q$,
  'P0001', 'forbidden', 'a manager cannot book');

select test_util.login('emp2');
select lives_ok($q$ select public.book_meals(array[test_util.id('one_seat')], gen_random_uuid()) $q$, 'first person takes the last seat');
select test_util.login('emp1');
select throws_ok($q$ select public.book_meals(array[test_util.id('one_seat')], gen_random_uuid()) $q$,
  'P0001', 'sold_out', 'a full meal cannot be booked');

-- ---------------------------------------------------------------------------
-- Cancellation
-- ---------------------------------------------------------------------------

select test_util.login('emp2');
select throws_ok($q$ select public.cancel_booking(test_util.booking('emp1', 'o2'), gen_random_uuid()) $q$,
  'P0001', 'booking_not_found', 'cannot cancel someone else''s booking');

select test_util.login('emp1');
select is((public.cancel_booking(test_util.booking('emp1', 'o2'), test_util.id('cancel-key'))->>'refunded')::bigint, 7000::bigint,
  'cancel before the deadline refunds the amount');
select is(test_util.balance('emp1'), '15000/5000', 'the refund returns to available');
select is((public.cancel_booking(test_util.booking('emp1', 'o2'), test_util.id('cancel-key'))->>'refunded')::bigint, 7000::bigint,
  'repeating a cancel returns the first answer');
select is(test_util.balance('emp1'), '15000/5000', 'a repeated cancel refunds once');
select throws_ok($q$ select public.cancel_booking(test_util.booking('emp1', 'o2'), gen_random_uuid()) $q$,
  'P0001', 'not_cancellable', 'a cancelled booking cannot be cancelled again');

select lives_ok($q$ select public.book_meals(array[test_util.id('o2')], gen_random_uuid()) $q$, 'a cancelled meal can be booked again');
select is(test_util.balance('emp1'), '8000/12000', 'booking again holds the amount again');
select lives_ok($q$ select public.cancel_booking(test_util.booking('emp1', 'o2'), gen_random_uuid()) $q$, 'cancel it to continue');

select lives_ok($q$ select public.book_meals(array[test_util.id('cancel_soon'), test_util.id('cancel_gone'), test_util.id('cancel_edge')], gen_random_uuid()) $q$,
  'book meals around the cancel deadline');
select lives_ok($q$ select public.cancel_booking(test_util.booking('emp1', 'cancel_soon'), gen_random_uuid()) $q$,
  'cancel one second before the deadline works');
select throws_ok($q$ select public.cancel_booking(test_util.booking('emp1', 'cancel_gone'), gen_random_uuid()) $q$,
  'P0001', 'cancel_deadline_passed', 'cancel one second after the deadline is rejected');
select throws_ok($q$ select public.cancel_booking(test_util.booking('emp1', 'cancel_edge'), gen_random_uuid()) $q$,
  'P0001', 'cancel_deadline_passed', 'cancel exactly at the deadline is rejected');

-- ---------------------------------------------------------------------------
-- Delegation and pickup
-- ---------------------------------------------------------------------------

select test_util.login('emp1');
select throws_ok($q$ select public.set_delegation('emp1', test_util.booking('emp1', 'o1'), gen_random_uuid()) $q$,
  'P0001', 'cannot_delegate_to_self', 'cannot delegate to yourself');
select throws_ok($q$ select public.set_delegation('emp4', test_util.booking('emp1', 'o1'), gen_random_uuid()) $q$,
  'P0001', 'colleague_not_found', 'cannot delegate to another restaurant');
select lives_ok($q$ select public.set_delegation('emp2', test_util.booking('emp1', 'o1'), gen_random_uuid()) $q$,
  'delegate one meal to a colleague');

select test_util.login('emp2');
select is((select count(*)::integer from public.my_pickups() where not is_mine and booking_id = test_util.booking('emp1', 'o1')), 1,
  'the delegate sees the colleague''s meal');
select throws_ok($q$ select public.cancel_booking(test_util.booking('emp1', 'o1'), gen_random_uuid()) $q$,
  'P0001', 'booking_not_found', 'a delegate cannot cancel the booking');
select throws_ok($q$ select public.set_delegation('emp3', test_util.booking('emp1', 'o1'), gen_random_uuid()) $q$,
  'P0001', 'booking_not_delegable', 'a delegate cannot pass the delegation on');
select is((select count(*)::integer from public.wallets where employee_id = test_util.id('emp1')), 0,
  'a delegate cannot see the colleague''s wallet');

select test_util.login('mgr1');
select is((select count(*)::integer from public.pickup_tokens), 0, 'a manager cannot read tokens');
select is(public.redeem_pickup(test_util.token('emp1', 'o1', 'emp1'), gen_random_uuid())->>'reason', 'not_started',
  'scanning before pickup time is rejected');
select is(public.redeem_pickup('not-a-real-token', gen_random_uuid())->>'reason', 'invalid_token', 'an unknown token is rejected');

select test_util.logout();
select test_util.open_pickup('o1');

select test_util.login('emp1');
select throws_ok($q$ select public.redeem_pickup(test_util.token('emp1', 'o1', 'emp1'), gen_random_uuid()) $q$,
  'P0001', 'forbidden', 'an employee cannot redeem');

select test_util.login('mgr2');
select is(public.redeem_pickup(test_util.token('emp1', 'o1', 'emp1'), gen_random_uuid())->>'reason', 'wrong_restaurant',
  'another restaurant cannot redeem');
select is(test_util.status('emp1', 'o1'), 'booked', 'a rejected scan changes nothing');

select test_util.login('mgr1');
select is(public.redeem_pickup(test_util.token('emp1', 'o1', 'emp2'), test_util.id('scan-key'))->>'ok', 'true', 'the delegate''s code is accepted');
select is(public.redeem_pickup(test_util.token('emp1', 'o1', 'emp2'), test_util.id('scan-key'))->>'ok', 'true', 'a network retry of the same scan succeeds');
select is(public.redeem_pickup(test_util.token('emp1', 'o1', 'emp1'), gen_random_uuid())->>'reason', 'already_picked_up',
  'the owner''s code no longer works after the delegate collected');
select is(public.redeem_pickup(test_util.token('emp1', 'o1', 'emp2'), gen_random_uuid())->>'picked_up_by_name', 'emp2',
  'a second scan reports who collected the meal');
select is(test_util.status('emp1', 'o1'), 'picked_up', 'the booking is collected');
select is(test_util.tx_count('emp1', 'o1', 'settle_pickup'), 1, 'the amount is settled exactly once');

-- Revoking a delegation invalidates only the delegate's code.
select test_util.login('emp2');
select lives_ok($q$ select public.set_delegation('emp1', test_util.booking('emp2', 'one_seat'), gen_random_uuid()) $q$, 'delegate a meal');
select lives_ok($q$ select public.revoke_delegation((select id from public.delegations where booking_id = test_util.booking('emp2', 'one_seat'))) $q$,
  'revoke the delegation');

select test_util.logout();
select test_util.open_pickup('one_seat');

select test_util.login('mgr1');
select is(public.redeem_pickup(test_util.token('emp2', 'one_seat', 'emp1'), gen_random_uuid())->>'reason', 'invalid_token',
  'a revoked delegate''s code is rejected');
select is(test_util.status('emp2', 'one_seat'), 'booked', 'revoking leaves the booking open');
select is(public.redeem_pickup(test_util.token('emp2', 'one_seat', 'emp2'), gen_random_uuid())->>'ok', 'true', 'the owner can still collect');

-- A standing delegation also covers meals booked later. The short code works too.
select test_util.login('admin');
select lives_ok($q$ select public.admin_top_up(array[test_util.id('emp3')], 30000, null, gen_random_uuid()) $q$, 'more balance for emp3');

select test_util.login('emp3');
select lives_ok($q$ select public.set_delegation('emp1', null, gen_random_uuid()) $q$, 'standing delegation');
select lives_ok($q$ select public.book_meals(array[test_util.id('standing')], gen_random_uuid()) $q$, 'book after delegating');

select test_util.login('emp1');
select is((select count(*)::integer from public.my_pickups() where booking_id = test_util.booking('emp3', 'standing')), 1,
  'the standing delegate gets a code for the new meal');

select test_util.logout();
select test_util.open_pickup('standing');

select test_util.login('mgr1');
select is(public.redeem_short_code(test_util.short_code('emp3', 'standing', 'emp1'), gen_random_uuid())->>'ok', 'true',
  'the short code collects the meal');
select is(public.redeem_short_code('000000x', gen_random_uuid())->>'reason', 'invalid_token', 'a wrong short code is rejected');

-- ---------------------------------------------------------------------------
-- No-show settlement and manual delivery
-- ---------------------------------------------------------------------------

select test_util.login('emp3');
select lives_ok($q$ select public.book_meals(array[test_util.id('expiring')], gen_random_uuid()) $q$, 'book a meal that will not be collected');
select test_util.logout();
select test_util.end_pickup('expiring');

select test_util.login('mgr1');
select is(public.redeem_pickup(test_util.token('emp3', 'expiring', 'emp3'), gen_random_uuid())->>'reason', 'expired',
  'scanning after pickup time is rejected');

select test_util.logout();
select is(private.settle_no_shows(), 1, 'the uncollected meal is settled');
select is(test_util.status('emp3', 'expiring'), 'no_show', 'the booking becomes no_show');
select is(private.settle_no_shows(), 0, 'running the job again settles nothing');
select is(test_util.tx_count('emp3', 'expiring', 'settle_no_show'), 1, 'the amount is deducted exactly once');

select test_util.login('mgr2');
select throws_ok($q$ select public.record_manual_delivery(test_util.booking('emp3', 'expiring'), 'outage', gen_random_uuid()) $q$,
  'P0001', 'booking_not_found', 'another restaurant cannot record a delivery');

select test_util.login('mgr1');
select throws_ok($q$ select public.record_manual_delivery(test_util.booking('emp3', 'expiring'), '', gen_random_uuid()) $q$,
  'P0001', 'reason_required', 'a manual delivery needs a reason');
select lives_ok($q$ select public.record_manual_delivery(test_util.booking('emp3', 'expiring'), 'internet outage', gen_random_uuid()) $q$,
  'record a delivery made during an outage');
select is(test_util.status('emp3', 'expiring'), 'picked_up', 'the status is corrected');
select is(test_util.tx_count('emp3', 'expiring', 'settle_pickup'), 0, 'correcting a no_show moves no money');

-- ---------------------------------------------------------------------------
-- Restaurant cancellation
-- ---------------------------------------------------------------------------

select test_util.login('emp2');
select lives_ok($q$ select public.book_meals(array[test_util.id('restaurant_cancels')], gen_random_uuid()) $q$, 'book a meal the restaurant will cancel');

select test_util.login('mgr2');
select throws_ok($q$ select public.cancel_offering(test_util.id('restaurant_cancels'), 'x', gen_random_uuid()) $q$,
  'P0001', 'offering_not_found', 'another restaurant cannot cancel it');

select test_util.login('mgr1');
select is((public.cancel_offering(test_util.id('restaurant_cancels'), 'kitchen closed', gen_random_uuid())->>'refunded_bookings')::integer, 1,
  'the manager cancels the meal');

select test_util.login('emp2');
select is(test_util.status('emp2', 'restaurant_cancels'), 'cancelled_by_restaurant', 'the booking is cancelled');
select is((select count(*)::integer from public.notifications where type = 'meal_cancelled'), 1, 'the employee is notified');
select is(test_util.tx_count('emp2', 'restaurant_cancels', 'release'), 1, 'the employee is refunded');

-- ---------------------------------------------------------------------------
-- Access control
-- ---------------------------------------------------------------------------

select test_util.login('emp1');
select is((select count(*)::integer from public.wallets), 1, 'an employee sees only their own wallet');
select is((select count(*)::integer from public.bookings where employee_id <> auth.uid()), 0, 'an employee sees only their own bookings');
select is((select count(*)::integer from public.meals where restaurant_id = test_util.id('rest2')), 0, 'an employee sees only their restaurant''s meals');
select throws_ok($q$ update public.wallets set available = 999999 $q$, '42501', null, 'an employee cannot change a wallet directly');
select throws_ok($q$ insert into public.bookings (employee_id, offering_id, restaurant_id, amount)
                     values (auth.uid(), test_util.id('o2'), test_util.id('rest1'), 1) $q$, '42501', null, 'an employee cannot insert a booking directly');
select throws_ok($q$ update public.bookings set status = 'cancelled' $q$, '42501', null, 'an employee cannot change a booking directly');
select throws_ok($q$ insert into public.wallet_transactions (employee_id, type, available_delta, held_delta)
                     values (auth.uid(), 'topup', 100, 0) $q$, '42501', null, 'an employee cannot write to the ledger');
select throws_ok($q$ select private.post_tx(auth.uid(), 'topup', 100, 0) $q$, '42501', null, 'an employee cannot call internal functions');
select throws_ok($q$ select private.settle_no_shows() $q$, '42501', null, 'an employee cannot run settlement');
select throws_ok($q$ insert into public.meals (restaurant_id, name, price) values (test_util.id('rest1'), 'x', 1) $q$,
  '42501', null, 'an employee cannot add a meal');
select lives_ok($q$ update public.profiles set role = 'admin' where id = auth.uid() $q$, 'a role change matches no row for a non-admin');
select is((select role::text from public.profiles where id = auth.uid()), 'employee', 'an employee cannot promote themselves');

select test_util.login('mgr1');
select is((select count(*)::integer from public.wallets), 0, 'a manager cannot see wallets');
select is((select count(*)::integer from public.wallet_transactions), 0, 'a manager cannot see the ledger');
select is((select count(*)::integer from public.bookings where restaurant_id <> test_util.id('rest1')), 0, 'a manager sees only their restaurant''s bookings');
select lives_ok($q$ insert into public.meals (restaurant_id, name, price) values (test_util.id('rest1'), 'New', 1000) $q$, 'a manager adds a meal to their restaurant');
select throws_ok($q$ insert into public.meals (restaurant_id, name, price) values (test_util.id('rest2'), 'x', 1) $q$,
  '42501', null, 'a manager cannot add a meal to another restaurant');

select test_util.login('admin');
select is((select count(*)::integer from public.wallets), 4, 'an admin sees every wallet');
select is((select count(*)::integer from public.pickup_tokens), 0, 'even an admin cannot read tokens');

select test_util.login('emp4');
select is(public.find_colleague('emp1'), null, 'colleague search does not cross restaurants');

select test_util.login('emp1');
select is(public.find_colleague(' EMP2 ')->>'full_name', 'emp2', 'colleague search finds an exact username');
select is(public.find_colleague('emp'), null, 'colleague search needs the full username');

-- ---------------------------------------------------------------------------
-- History and integrity
-- ---------------------------------------------------------------------------

select test_util.logout();
select throws_ok($q$ update public.wallet_transactions set available_delta = 1 $q$, 'P0001', 'history_is_append_only', 'the ledger cannot be edited, even by the owner');
select throws_ok($q$ delete from public.wallet_transactions $q$, 'P0001', 'history_is_append_only', 'the ledger cannot be deleted from');
select is(private.check_wallet_integrity(), 0, 'every wallet matches its ledger and open bookings');

-- ---------------------------------------------------------------------------
-- Ramadan
-- ---------------------------------------------------------------------------

insert into public.schedules (
  restaurant_id, meal_id, period, season, weekdays, start_date,
  book_day_offset, book_time, cancel_day_offset, cancel_time,
  pickup_from_day_offset, pickup_from_time, pickup_until_day_offset, pickup_until_time
) values
  (test_util.id('rest2'), test_util.id('mealr2'), 'lunch', 'normal', '{0,1,2,3,4,5,6}', current_date - 1,
   -1, '20:00', 0, '08:00', 0, '12:00', 0, '14:30'),
  (test_util.id('rest2'), test_util.id('iftar2'), 'iftar', 'ramadan', '{0,1,2,3,4,5,6}', current_date - 1,
   0, '10:00', 0, '12:00', 0, '17:00', 0, '19:30');

select throws_ok($q$ insert into public.schedules (
    restaurant_id, meal_id, period, season, weekdays, start_date,
    book_day_offset, book_time, cancel_day_offset, cancel_time,
    pickup_from_day_offset, pickup_from_time, pickup_until_day_offset, pickup_until_time
  ) values (test_util.id('rest2'), test_util.id('mealr2'), 'lunch', 'ramadan', '{1}', current_date,
    0, '08:00', 0, '08:00', 0, '12:00', 0, '14:00') $q$, '23514', null, 'lunch cannot be a Ramadan meal');
select throws_ok($q$ insert into public.schedules (
    restaurant_id, meal_id, period, season, weekdays, start_date,
    book_day_offset, book_time, cancel_day_offset, cancel_time,
    pickup_from_day_offset, pickup_from_time, pickup_until_day_offset, pickup_until_time
  ) values (test_util.id('rest2'), test_util.id('mealr2'), 'lunch', 'normal', '{1}', current_date,
    0, '13:00', 0, '08:00', 0, '12:00', 0, '14:00') $q$, '23514', null, 'booking cannot close after pickup starts');

select test_util.login('emp1');
select throws_ok($q$ select public.set_ramadan_period(1448, current_date, current_date + 1, gen_random_uuid()) $q$,
  'P0001', 'forbidden', 'only an admin sets Ramadan dates');

select test_util.login('admin');
select lives_ok($q$ select public.set_ramadan_period(1448, (current_date + 7)::date, (current_date + 9)::date, gen_random_uuid()) $q$,
  'admin sets Ramadan dates');

select test_util.logout();
select is((select count(*)::integer from public.meal_offerings
           where restaurant_id = test_util.id('rest2')
             and service_date between current_date + 7 and current_date + 9
             and period not in ('suhoor', 'iftar')), 0,
  'during Ramadan only suhoor and iftar are generated');
select is((select count(*)::integer from public.meal_offerings
           where restaurant_id = test_util.id('rest2')
             and service_date between current_date + 7 and current_date + 9
             and period = 'iftar'), 3,
  'iftar is generated for each Ramadan day');
select is((select count(*)::integer from public.meal_offerings
           where restaurant_id = test_util.id('rest2')
             and service_date = current_date + 10 and period = 'lunch'), 1,
  'normal meals return after Ramadan');
select is((select count(*)::integer from public.meal_offerings
           where restaurant_id = test_util.id('rest2')
             and service_date = current_date + 10 and period = 'iftar'), 0,
  'no iftar is generated after Ramadan');

select test_util.login('emp4');
select lives_ok($q$ select public.book_meals(
    array(select id from public.meal_offerings where service_date = current_date + 10 and period = 'lunch'),
    gen_random_uuid()) $q$, 'book lunch for the day after Ramadan');
select is(test_util.balance('emp4'), '14000/6000', 'lunch is held');

select test_util.login('admin');
select is((public.preview_ramadan_change(1448, (current_date + 7)::date, (current_date + 10)::date)->>'bookings_to_refund')::integer, 1,
  'the preview shows the affected booking');
select is(test_util.balance('emp4'), '14000/6000', 'the preview changes nothing');
select is((public.set_ramadan_period(1448, (current_date + 7)::date, (current_date + 10)::date, gen_random_uuid())->>'refunded_bookings')::integer, 1,
  'extending Ramadan cancels the lunch');
select is(test_util.balance('emp4'), '20000/0', 'the employee is refunded');

select test_util.logout();
select is((select count(*)::integer from public.meal_offerings
           where restaurant_id = test_util.id('rest2')
             and service_date = current_date + 10 and period = 'iftar'), 1,
  'iftar is generated for the new Ramadan day');
select is((select status::text from public.meal_offerings
           where restaurant_id = test_util.id('rest2')
             and service_date = current_date + 10 and period = 'lunch'), 'cancelled',
  'the lunch offering is cancelled');

select is(private.check_wallet_integrity(), 0, 'wallets still match after the Ramadan refund');

update public.wallets set available = available + 1 where employee_id = test_util.id('emp4');
select is(private.check_wallet_integrity(), 1, 'a wallet that does not match its ledger is detected');
select is((select count(*)::integer from public.notifications where type = 'integrity_alert' and user_id = test_util.id('admin')), 1,
  'the admin is alerted');

select * from finish();
rollback;
