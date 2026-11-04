-- Account changes that must stay in step with Supabase Auth go through Edge Functions:
-- the username is the login, and deactivating must also block sign-in.
revoke update (username, is_active) on public.profiles from authenticated;

-- Signs a user out of every device. Called by Edge Functions with the service role.
create function public.revoke_user_sessions(p_user_id uuid)
returns void
language sql
security definer
set search_path = public, private, pg_temp
as $$
  delete from auth.sessions where user_id = p_user_id;
$$;

revoke all on function public.revoke_user_sessions(uuid) from public, anon, authenticated;
grant execute on function public.revoke_user_sessions(uuid) to service_role;
