-- TEST ONLY. Stands in for Supabase's auth schema and assertion helpers.
-- Never loaded into a real Supabase project.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key default gen_random_uuid());
create or replace function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;

create or replace function public.t_assert(ok boolean, msg text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'ASSERT FAILED: %', msg; end if;
end $$;

create or replace function public.t_expect_error(q text) returns void language plpgsql as $$
begin
  execute q;
  raise exception 'EXPECTED AN ERROR BUT NONE HAPPENED: %', left(q, 90);
exception when others then
  if sqlerrm like 'EXPECTED AN ERROR%' then raise; end if;
end $$;
