#!/usr/bin/env bash
# Sends truly simultaneous requests from separate database sessions and checks that
# money and seats stay correct. Commits data, so run it only on a throwaway local
# database: `supabase start`, then `bash scripts/concurrency-test.sh`.

set -u

DB="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
OUT="$(mktemp -d)"
failures=0

q() {
  psql "$DB" -X -q -t -A -v ON_ERROR_STOP=1 -c "$1"
}

# Runs one statement as a signed-in user. Rejections are expected in these scenarios,
# so errors go to the output file and do not stop the script.
as_user() {
  psql "$DB" -X -q -t -A <<SQL
begin;
select set_config('request.jwt.claims', json_build_object('sub', md5('$1')::uuid, 'role', 'authenticated')::text, true);
set local role authenticated;
$2;
commit;
SQL
}

expect() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1 (expected '$3', got '$2')"
    failures=$((failures + 1))
  fi
}

q "
insert into public.sites (id, name) values (md5('site')::uuid, 'Site');
insert into public.restaurants (id, site_id, name, timezone)
  values (md5('rest')::uuid, md5('site')::uuid, 'Restaurant', 'Asia/Baghdad');
insert into public.meals (id, restaurant_id, name, price)
  values (md5('meal')::uuid, md5('rest')::uuid, 'Rice', 1000);

insert into auth.users (id, email)
  select md5(name)::uuid, name || '@meals.invalid'
  from unnest(array['admin1','mgr1','emp1','emp2','emp3','emp4','emp5','emp6','emp7','emp8']) as name;

insert into public.profiles (id, username, full_name, role)
  values (md5('admin1')::uuid, 'admin1', 'admin1', 'admin');
insert into public.profiles (id, username, full_name, role, site_id, restaurant_id)
  values (md5('mgr1')::uuid, 'mgr1', 'mgr1', 'manager', md5('site')::uuid, md5('rest')::uuid);
insert into public.profiles (id, username, full_name, role, site_id, restaurant_id)
  select md5(name)::uuid, name, name, 'employee', md5('site')::uuid, md5('rest')::uuid
  from unnest(array['emp1','emp2','emp3','emp4','emp5','emp6','emp7','emp8']) as name;

create function public.conc_add_offering(p_name text, p_days integer, p_capacity integer default null)
returns void language sql as \$\$
  insert into public.meal_offerings (
    id, meal_id, restaurant_id, service_date, period, season, price,
    book_until, cancel_until, pickup_from, pickup_until, capacity
  ) values (
    md5(p_name)::uuid, md5('meal')::uuid, md5('rest')::uuid, current_date + p_days, 'lunch', 'normal', 1000,
    now() + interval '1 day', now() + interval '1 day', now() + interval '2 days', now() + interval '3 days', p_capacity
  );
\$\$;
" || { echo "setup failed"; exit 1; }

as_user admin1 "select public.admin_top_up(array[md5('emp1')::uuid], 1000, null, gen_random_uuid())" > /dev/null
as_user admin1 "select public.admin_top_up(array[md5('emp2')::uuid, md5('emp3')::uuid, md5('emp4')::uuid, md5('emp5')::uuid, md5('emp6')::uuid, md5('emp7')::uuid, md5('emp8')::uuid], 100000, null, gen_random_uuid())" > /dev/null

# ---------------------------------------------------------------------------
echo "# Last balance: 8 simultaneous bookings, money for only one"
for i in 1 2 3 4 5 6 7 8; do
  q "select public.conc_add_offering('balance$i', $i)" > /dev/null
done
for i in 1 2 3 4 5 6 7 8; do
  as_user emp1 "select public.book_meals(array[md5('balance$i')::uuid], gen_random_uuid())" > "$OUT/a$i" 2>&1 &
done
wait
expect "exactly one booking succeeds" "$(q "select count(*) from public.bookings where employee_id = md5('emp1')::uuid and status = 'booked'")" "1"
expect "balance never goes negative" "$(q "select available || '/' || held from public.wallets where employee_id = md5('emp1')::uuid")" "0/1000"

# ---------------------------------------------------------------------------
echo "# Last seat: 7 people book a meal with one seat at the same moment"
q "select public.conc_add_offering('seat', 20, 1)" > /dev/null
for i in 2 3 4 5 6 7 8; do
  as_user "emp$i" "select public.book_meals(array[md5('seat')::uuid], gen_random_uuid())" > "$OUT/b$i" 2>&1 &
done
wait
expect "exactly one person gets the seat" "$(q "select count(*) from public.bookings where offering_id = md5('seat')::uuid")" "1"
expect "the seat counter is right" "$(q "select booked_count from public.meal_offerings where id = md5('seat')::uuid")" "1"

# ---------------------------------------------------------------------------
echo "# Double tap: the same request sent 6 times at once"
q "select public.conc_add_offering('retry', 21)" > /dev/null
before="$(q "select available from public.wallets where employee_id = md5('emp2')::uuid")"
key="$(q "select gen_random_uuid()")"
for i in 1 2 3 4 5 6; do
  as_user emp2 "select public.book_meals(array[md5('retry')::uuid], '$key')" > "$OUT/c$i" 2>&1 &
done
wait
expect "only one booking exists" "$(q "select count(*) from public.bookings where employee_id = md5('emp2')::uuid and offering_id = md5('retry')::uuid")" "1"
expect "the amount is deducted once" "$(q "select $before - available from public.wallets where employee_id = md5('emp2')::uuid")" "1000"
expect "every request gets the same answer" "$(cat "$OUT"/c? | grep -c '"booking_ids"')" "6"

# ---------------------------------------------------------------------------
echo "# Same meal, two codes: owner and delegate scanned at the same moment, 15 rounds"
all_one_ok=1
for round in $(seq 1 15); do
  name="scan$round"
  q "select public.conc_add_offering('$name', 30 + $round)" > /dev/null
  as_user emp3 "select public.book_meals(array[md5('$name')::uuid], gen_random_uuid())" > /dev/null
  booking="$(q "select id from public.bookings where offering_id = md5('$name')::uuid")"
  as_user emp3 "select public.set_delegation('emp4', '$booking', gen_random_uuid())" > /dev/null
  q "update public.meal_offerings
     set book_until = now() - interval '3 hours', cancel_until = now() - interval '3 hours',
         pickup_from = now() - interval '1 hour', pickup_until = now() + interval '1 hour'
     where id = md5('$name')::uuid" > /dev/null
  owner_token="$(q "select token from public.pickup_tokens where booking_id = '$booking' and holder_id = md5('emp3')::uuid")"
  delegate_token="$(q "select token from public.pickup_tokens where booking_id = '$booking' and holder_id = md5('emp4')::uuid")"

  as_user mgr1 "select public.redeem_pickup('$owner_token', gen_random_uuid())" > "$OUT/d1" 2>&1 &
  as_user mgr1 "select public.redeem_pickup('$delegate_token', gen_random_uuid())" > "$OUT/d2" 2>&1 &
  wait

  accepted="$(cat "$OUT/d1" "$OUT/d2" | grep -c '"ok": true')"
  settled="$(q "select count(*) from public.wallet_transactions where booking_id = '$booking' and type = 'settle_pickup'")"
  if [ "$accepted" != "1" ] || [ "$settled" != "1" ]; then
    echo "round $round: accepted=$accepted settled=$settled"
    all_one_ok=0
  fi
done
expect "one scan wins and the amount settles once, in every round" "$all_one_ok" "1"

# ---------------------------------------------------------------------------
echo "# The restaurant cancels a meal while people are booking it, 5 rounds"
all_clean=1
for round in 1 2 3 4 5; do
  name="race$round"
  q "select public.conc_add_offering('$name', 60 + $round)" > /dev/null
  as_user emp5 "select public.book_meals(array[md5('$name')::uuid], gen_random_uuid())" > /dev/null
  for i in 6 7 8; do
    as_user "emp$i" "select public.book_meals(array[md5('$name')::uuid], gen_random_uuid())" > "$OUT/e$i" 2>&1 &
  done
  as_user mgr1 "select public.cancel_offering(md5('$name')::uuid, 'kitchen closed', gen_random_uuid())" > "$OUT/e0" 2>&1 &
  wait

  state="$(q "select o.status || '/' || o.booked_count || '/' || (select count(*) from public.bookings b where b.offering_id = o.id and b.status = 'booked')
              from public.meal_offerings o where o.id = md5('$name')::uuid")"
  case "$state" in
    cancelled/0/0) ;;
    *)
      echo "round $round: status/booked_count/open bookings = $state"
      cat "$OUT/e0"
      all_clean=0
      ;;
  esac
done
expect "no booking stays open on a cancelled meal" "$all_clean" "1"

# ---------------------------------------------------------------------------
echo "# Final check"
expect "every wallet matches its ledger and open bookings" "$(q "select private.check_wallet_integrity()")" "0"

rm -rf "$OUT"

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All concurrency checks passed"
