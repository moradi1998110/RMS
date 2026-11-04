-- Core schema: organisation, menu, bookings, pickup and the wallet ledger.
-- Amounts are whole currency units in bigint. All deadlines are timestamptz and
-- are only ever compared to the server clock.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;

create type public.user_role as enum ('admin', 'manager', 'employee');
create type public.meal_period as enum ('breakfast', 'lunch', 'dinner', 'suhoor', 'iftar');
create type public.season_type as enum ('normal', 'ramadan');
create type public.repeat_type as enum ('weekly', 'one_week');
create type public.offering_status as enum ('open', 'cancelled');
create type public.booking_status as enum ('booked', 'cancelled', 'cancelled_by_restaurant', 'picked_up', 'no_show');
create type public.pickup_method as enum ('scan', 'short_code', 'manual');
create type public.delegation_scope as enum ('booking', 'standing');
create type public.wallet_tx_type as enum ('topup', 'hold', 'release', 'settle_pickup', 'settle_no_show', 'adjustment');

-- Minutes from midnight of the service date; lets a table CHECK compare "day offset + time" values.
create function private.offset_minutes(p_day_offset integer, p_time time)
returns integer
language sql
immutable
as $$
  select p_day_offset * 1440 + (extract(epoch from p_time) / 60)::integer;
$$;

-- ---------------------------------------------------------------------------
-- Organisation
-- ---------------------------------------------------------------------------

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.restaurants (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  name text not null check (btrim(name) <> ''),
  timezone text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, site_id)
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete restrict,
  username text not null unique check (username ~ '^[a-z0-9._-]{3,32}$'),
  full_name text not null check (btrim(full_name) <> ''),
  department text,
  role public.user_role not null,
  site_id uuid references public.sites (id),
  restaurant_id uuid,
  is_active boolean not null default true,
  must_change_password boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key (restaurant_id, site_id) references public.restaurants (id, site_id),
  check (
    (role = 'admin' and restaurant_id is null)
    or (role <> 'admin' and restaurant_id is not null and site_id is not null)
  )
);

create index profiles_restaurant_idx on public.profiles (restaurant_id);

-- ---------------------------------------------------------------------------
-- Menu and scheduling
-- ---------------------------------------------------------------------------

create table public.meals (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants (id),
  name text not null check (btrim(name) <> ''),
  description text not null default '',
  image_path text,
  price bigint not null check (price > 0),
  has_salad boolean not null default false,
  has_soft_drink boolean not null default false,
  has_juice boolean not null default false,
  has_vegetables boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, restaurant_id)
);

create index meals_restaurant_idx on public.meals (restaurant_id);

create table public.time_defaults (
  restaurant_id uuid not null references public.restaurants (id),
  period public.meal_period not null,
  season public.season_type not null,
  book_day_offset integer not null,
  book_time time not null,
  cancel_day_offset integer not null,
  cancel_time time not null,
  pickup_from_day_offset integer not null,
  pickup_from_time time not null,
  pickup_until_day_offset integer not null,
  pickup_until_time time not null,
  primary key (restaurant_id, period, season),
  check ((season = 'ramadan') = (period in ('suhoor', 'iftar'))),
  check (private.offset_minutes(book_day_offset, book_time) <= private.offset_minutes(pickup_from_day_offset, pickup_from_time)),
  check (private.offset_minutes(cancel_day_offset, cancel_time) <= private.offset_minutes(pickup_from_day_offset, pickup_from_time)),
  check (private.offset_minutes(pickup_from_day_offset, pickup_from_time) < private.offset_minutes(pickup_until_day_offset, pickup_until_time))
);

-- Keyed by Hijri year: a Gregorian year can contain two Ramadans (2030 does).
create table public.ramadan_periods (
  hijri_year integer primary key check (hijri_year > 1400),
  start_date date not null,
  end_date date not null,
  check (start_date <= end_date)
);

create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null,
  meal_id uuid not null,
  period public.meal_period not null,
  season public.season_type not null,
  weekdays smallint[] not null, -- 0 = Sunday ... 6 = Saturday, matching extract(dow)
  repeat_type public.repeat_type not null default 'weekly',
  start_date date not null,
  end_date date,
  capacity integer check (capacity > 0),
  book_day_offset integer not null,
  book_time time not null,
  cancel_day_offset integer not null,
  cancel_time time not null,
  pickup_from_day_offset integer not null,
  pickup_from_time time not null,
  pickup_until_day_offset integer not null,
  pickup_until_time time not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key (meal_id, restaurant_id) references public.meals (id, restaurant_id),
  check (cardinality(weekdays) > 0 and weekdays <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]),
  check (end_date is null or start_date <= end_date),
  check (repeat_type = 'weekly' or (end_date is not null and end_date <= start_date + 6)),
  check ((season = 'ramadan') = (period in ('suhoor', 'iftar'))),
  check (private.offset_minutes(book_day_offset, book_time) <= private.offset_minutes(pickup_from_day_offset, pickup_from_time)),
  check (private.offset_minutes(cancel_day_offset, cancel_time) <= private.offset_minutes(pickup_from_day_offset, pickup_from_time)),
  check (private.offset_minutes(pickup_from_day_offset, pickup_from_time) < private.offset_minutes(pickup_until_day_offset, pickup_until_time))
);

create index schedules_restaurant_idx on public.schedules (restaurant_id) where is_active;

-- One concrete meal on one date. Price and times are snapshots, so later edits to
-- a meal or schedule never change what an existing booking agreed to.
create table public.meal_offerings (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid references public.schedules (id),
  meal_id uuid not null,
  restaurant_id uuid not null,
  service_date date not null,
  period public.meal_period not null,
  season public.season_type not null,
  price bigint not null check (price > 0),
  book_until timestamptz not null,
  cancel_until timestamptz not null,
  pickup_from timestamptz not null,
  pickup_until timestamptz not null,
  capacity integer check (capacity > 0),
  booked_count integer not null default 0 check (booked_count >= 0),
  status public.offering_status not null default 'open',
  cancel_reason text,
  created_at timestamptz not null default now(),
  foreign key (meal_id, restaurant_id) references public.meals (id, restaurant_id),
  unique (meal_id, service_date, period),
  check (book_until <= pickup_from),
  check (cancel_until <= pickup_from),
  check (pickup_from < pickup_until),
  check (capacity is null or booked_count <= capacity)
);

create index meal_offerings_menu_idx on public.meal_offerings (restaurant_id, service_date);

-- ---------------------------------------------------------------------------
-- Bookings, pickup and delegation
-- ---------------------------------------------------------------------------

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles (id),
  offering_id uuid not null references public.meal_offerings (id),
  restaurant_id uuid not null references public.restaurants (id),
  amount bigint not null check (amount > 0),
  status public.booking_status not null default 'booked',
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  settled_at timestamptz,
  picked_up_at timestamptz,
  picked_up_by uuid references public.profiles (id),
  scanned_by uuid references public.profiles (id),
  pickup_method public.pickup_method,
  check (status <> 'picked_up' or (picked_up_at is not null and picked_up_by is not null and pickup_method is not null))
);

-- A cancelled booking does not block booking the same meal again.
create unique index bookings_one_live_per_offering
  on public.bookings (employee_id, offering_id)
  where status not in ('cancelled', 'cancelled_by_restaurant');

create index bookings_employee_idx on public.bookings (employee_id, created_at desc);
create index bookings_offering_idx on public.bookings (offering_id);
create index bookings_restaurant_idx on public.bookings (restaurant_id);
create index bookings_open_idx on public.bookings (offering_id) where status = 'booked';

create table public.delegations (
  id uuid primary key default gen_random_uuid(),
  delegator_id uuid not null references public.profiles (id),
  delegate_id uuid not null references public.profiles (id),
  scope public.delegation_scope not null,
  booking_id uuid references public.bookings (id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  check (delegator_id <> delegate_id),
  check ((scope = 'booking') = (booking_id is not null))
);

create unique index delegations_one_standing
  on public.delegations (delegator_id)
  where scope = 'standing' and revoked_at is null;

create unique index delegations_one_per_booking
  on public.delegations (booking_id)
  where scope = 'booking' and revoked_at is null;

create index delegations_delegate_idx on public.delegations (delegate_id) where revoked_at is null;

-- Each holder of a booking gets their own token, so the record shows who actually
-- collected the meal. Tokens carry no personal data.
create table public.pickup_tokens (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id),
  holder_id uuid not null references public.profiles (id),
  restaurant_id uuid not null references public.restaurants (id),
  delegation_id uuid references public.delegations (id),
  token text not null unique,
  short_code text not null check (short_code ~ '^[0-9]{6}$'),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create unique index pickup_tokens_one_live_per_holder
  on public.pickup_tokens (booking_id, holder_id)
  where revoked_at is null;

create unique index pickup_tokens_live_short_code
  on public.pickup_tokens (restaurant_id, short_code)
  where revoked_at is null;

create index pickup_tokens_holder_idx on public.pickup_tokens (holder_id) where revoked_at is null;
create index pickup_tokens_delegation_idx on public.pickup_tokens (delegation_id) where revoked_at is null;

-- ---------------------------------------------------------------------------
-- Wallet ledger
-- ---------------------------------------------------------------------------

create table public.wallets (
  employee_id uuid primary key references public.profiles (id),
  available bigint not null default 0 check (available >= 0),
  held bigint not null default 0 check (held >= 0),
  updated_at timestamptz not null default now()
);

create table public.wallet_transactions (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.wallets (employee_id),
  type public.wallet_tx_type not null,
  available_delta bigint not null,
  held_delta bigint not null,
  booking_id uuid references public.bookings (id),
  note text,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  check (
    case type
      when 'topup' then available_delta > 0 and held_delta = 0
      when 'hold' then available_delta < 0 and held_delta = -available_delta
      when 'release' then available_delta > 0 and held_delta = -available_delta
      when 'settle_pickup' then available_delta = 0 and held_delta < 0
      when 'settle_no_show' then available_delta = 0 and held_delta < 0
      when 'adjustment' then available_delta <> 0 and held_delta = 0 and btrim(coalesce(note, '')) <> ''
    end
  )
);

create index wallet_transactions_employee_idx on public.wallet_transactions (employee_id, id desc);
create index wallet_transactions_booking_idx on public.wallet_transactions (booking_id);

-- ---------------------------------------------------------------------------
-- Support tables
-- ---------------------------------------------------------------------------

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  entity text not null,
  entity_id text,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- Outbox read by the push-notification function.
create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id),
  type text not null,
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index notifications_user_idx on public.notifications (user_id, id desc);
create index notifications_unsent_idx on public.notifications (id) where sent_at is null;

create table public.integrity_alerts (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.wallets (employee_id),
  details jsonb not null,
  created_at timestamptz not null default now()
);

create table private.idempotency_keys (
  actor_id uuid not null,
  operation text not null,
  key uuid not null,
  response jsonb,
  created_at timestamptz not null default now(),
  primary key (actor_id, operation, key)
);

create table private.colleague_lookups (
  user_id uuid not null,
  created_at timestamptz not null default now()
);

create index colleague_lookups_idx on private.colleague_lookups (user_id, created_at);

-- ---------------------------------------------------------------------------
-- Append-only guard for financial and audit history
-- ---------------------------------------------------------------------------

create function private.reject_history_change()
returns trigger
language plpgsql
as $$
begin
  raise exception 'history_is_append_only' using errcode = 'P0001';
end;
$$;

create trigger wallet_transactions_append_only
  before update or delete on public.wallet_transactions
  for each row execute function private.reject_history_change();

create trigger wallet_transactions_no_truncate
  before truncate on public.wallet_transactions
  for each statement execute function private.reject_history_change();

create trigger audit_log_append_only
  before update or delete on public.audit_log
  for each row execute function private.reject_history_change();

create trigger audit_log_no_truncate
  before truncate on public.audit_log
  for each statement execute function private.reject_history_change();

-- Every employee has a wallet from the moment the profile exists.
create function private.ensure_wallet()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if new.role = 'employee' then
    insert into public.wallets (employee_id) values (new.id)
    on conflict (employee_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger profiles_ensure_wallet
  after insert or update of role on public.profiles
  for each row execute function private.ensure_wallet();
