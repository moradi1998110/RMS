-- App releases: the newest one is offered to every phone, a mandatory one sets the oldest allowed
-- build, and no one can write releases from the app. The files themselves are public.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(public.latest_app_release(), null, 'nothing is offered before the first release');

insert into public.app_releases (build, version, notes, mandatory, files) values
  (10, '1.0.0', 'First', false, '{"arm64-v8a": {"path": "10/zad-arm64-v8a.apk", "sha256": "aa", "size": 1}}'),
  (12, '1.0.0', 'Must update', true, '{"arm64-v8a": {"path": "12/zad-arm64-v8a.apk", "sha256": "bb", "size": 1}}'),
  (15, '1.0.0', 'Newest', false, '{"arm64-v8a": {"path": "15/zad-arm64-v8a.apk", "sha256": "cc", "size": 1}}');

set local role anon;
select is((public.latest_app_release()->>'build')::integer, 15, 'the newest release is offered, even before signing in');
select is((public.latest_app_release()->>'min_build')::integer, 12, 'builds before the last mandatory one must update');
select is(public.latest_app_release()->'files'->'arm64-v8a'->>'sha256', 'cc', 'with its file and fingerprint');

reset role;
set local role authenticated;
select throws_ok($q$ insert into public.app_releases (build, version, files) values (99, 'x', '{}') $q$,
  '42501', null, 'the app cannot add a release');
select throws_ok($q$ select * from public.app_releases $q$, '42501', null, 'nor read the table directly');

select * from finish();
rollback;
