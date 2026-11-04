-- Identity helpers and row level security.
-- Money, bookings, tokens and delegations have no direct write grants at all:
-- they change only through the security definer functions in later migrations.

create function private.app_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select role from public.profiles where id = auth.uid() and is_active;
$$;

create function private.my_restaurant_id()
returns uuid
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select restaurant_id from public.profiles where id = auth.uid() and is_active;
$$;

create function private.is_admin()
returns boolean
language sql
stable
as $$
  select coalesce(private.app_role() = 'admin', false);
$$;

create function private.manages(p_restaurant_id uuid)
returns boolean
language sql
stable
as $$
  select coalesce(private.app_role() = 'manager' and private.my_restaurant_id() = p_restaurant_id, false);
$$;

alter table public.sites enable row level security;
alter table public.restaurants enable row level security;
alter table public.profiles enable row level security;
alter table public.meals enable row level security;
alter table public.time_defaults enable row level security;
alter table public.ramadan_periods enable row level security;
alter table public.schedules enable row level security;
alter table public.meal_offerings enable row level security;
alter table public.bookings enable row level security;
alter table public.delegations enable row level security;
alter table public.pickup_tokens enable row level security;
alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.audit_log enable row level security;
alter table public.notifications enable row level security;
alter table public.integrity_alerts enable row level security;

-- Organisation
create policy sites_read on public.sites for select to authenticated
  using (
    private.is_admin()
    or id = (select site_id from public.restaurants where id = private.my_restaurant_id())
  );
create policy sites_admin_insert on public.sites for insert to authenticated with check (private.is_admin());
create policy sites_admin_update on public.sites for update to authenticated
  using (private.is_admin()) with check (private.is_admin());

create policy restaurants_read on public.restaurants for select to authenticated
  using (private.is_admin() or id = private.my_restaurant_id());
create policy restaurants_admin_insert on public.restaurants for insert to authenticated with check (private.is_admin());
create policy restaurants_admin_update on public.restaurants for update to authenticated
  using (private.is_admin()) with check (private.is_admin());

create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or private.is_admin() or private.manages(restaurant_id));
create policy profiles_admin_update on public.profiles for update to authenticated
  using (private.is_admin()) with check (private.is_admin());

-- Menu
create policy meals_read on public.meals for select to authenticated
  using (private.is_admin() or restaurant_id = private.my_restaurant_id());
create policy meals_manager_insert on public.meals for insert to authenticated
  with check (private.manages(restaurant_id));
create policy meals_manager_update on public.meals for update to authenticated
  using (private.manages(restaurant_id)) with check (private.manages(restaurant_id));

create policy time_defaults_read on public.time_defaults for select to authenticated
  using (private.is_admin() or private.manages(restaurant_id));
create policy time_defaults_manager_insert on public.time_defaults for insert to authenticated
  with check (private.manages(restaurant_id));
create policy time_defaults_manager_update on public.time_defaults for update to authenticated
  using (private.manages(restaurant_id)) with check (private.manages(restaurant_id));

create policy ramadan_read on public.ramadan_periods for select to authenticated using (true);

create policy schedules_read on public.schedules for select to authenticated
  using (private.is_admin() or private.manages(restaurant_id));
create policy schedules_manager_insert on public.schedules for insert to authenticated
  with check (private.manages(restaurant_id));
create policy schedules_manager_update on public.schedules for update to authenticated
  using (private.manages(restaurant_id)) with check (private.manages(restaurant_id));

create policy offerings_read on public.meal_offerings for select to authenticated
  using (private.is_admin() or restaurant_id = private.my_restaurant_id());

-- Bookings and pickup
create policy bookings_read on public.bookings for select to authenticated
  using (employee_id = auth.uid() or private.is_admin() or private.manages(restaurant_id));

create policy delegations_read on public.delegations for select to authenticated
  using (delegator_id = auth.uid() or delegate_id = auth.uid() or private.is_admin());

-- Only the holder can ever read a token. Managers and admins deliberately cannot,
-- otherwise they could redeem a meal on someone's behalf.
create policy pickup_tokens_read on public.pickup_tokens for select to authenticated
  using (holder_id = auth.uid());

-- Wallet: managers do not see balances.
create policy wallets_read on public.wallets for select to authenticated
  using (employee_id = auth.uid() or private.is_admin());

create policy wallet_transactions_read on public.wallet_transactions for select to authenticated
  using (employee_id = auth.uid() or private.is_admin());

-- Support
create policy audit_log_read on public.audit_log for select to authenticated using (private.is_admin());
create policy notifications_read on public.notifications for select to authenticated using (user_id = auth.uid());
create policy integrity_alerts_read on public.integrity_alerts for select to authenticated using (private.is_admin());

-- Grants. Supabase's default privileges hand everything to anon and authenticated,
-- so start from nothing and add back only what the policies above expect.
revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

alter default privileges in schema public revoke all on tables from public, anon, authenticated;
alter default privileges in schema public revoke all on sequences from public, anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;
alter default privileges in schema private revoke all on functions from public, anon, authenticated;

grant usage on schema public to authenticated;
grant usage on schema private to authenticated;

grant execute on function private.app_role() to authenticated;
grant execute on function private.my_restaurant_id() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.manages(uuid) to authenticated;
-- Used by CHECK constraints on tables managers write to; constraints run as the caller.
grant execute on function private.offset_minutes(integer, time) to authenticated;

grant select on all tables in schema public to authenticated;

grant insert, update on public.sites, public.restaurants to authenticated;
grant insert, update on public.meals, public.time_defaults, public.schedules to authenticated;
grant update (username, full_name, department, role, site_id, restaurant_id, is_active) on public.profiles to authenticated;
