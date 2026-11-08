-- Published versions of the Android app, so the app can offer its own updates: it is
-- installed from a file, not from the Play Store. The release workflow uploads the APK
-- files to the app-releases bucket and adds a row here with the secret key; nobody
-- writes them from the app.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('app-releases', 'app-releases', true, 62914560, array['application/vnd.android.package-archive'])
on conflict (id) do nothing;

create table public.app_releases (
  -- Android's version code: it only ever rises, and decides what is newer.
  build integer primary key check (build > 0),
  version text not null,
  notes text not null default '',
  -- Every build before a mandatory one must update before it can be used.
  mandatory boolean not null default false,
  -- One file per processor type: {"arm64-v8a": {"path": ..., "sha256": ..., "size": ...}}
  files jsonb not null check (jsonb_typeof(files) = 'object'),
  published_at timestamptz not null default now()
);

alter table public.app_releases enable row level security;

-- The newest release, with the oldest build still allowed. Readable before signing in
-- too, so a phone too old to work can still be told to update. Holds no personal data.
create function public.latest_app_release()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select jsonb_build_object(
    'build', r.build,
    'version', r.version,
    'notes', r.notes,
    'files', r.files,
    'published_at', r.published_at,
    'min_build', coalesce((select max(m.build) from public.app_releases m where m.mandatory), 0)
  )
  from public.app_releases r
  order by r.build desc
  limit 1;
$$;

revoke all on function public.latest_app_release() from public;
grant execute on function public.latest_app_release() to anon, authenticated;
