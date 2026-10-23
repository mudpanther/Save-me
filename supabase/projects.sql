-- The kingdom's weekly project: one choice per week, narrative only.
-- A project never changes balances, rarity or rewards. Run after goals.sql.
create table if not exists public.kingdom_projects (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  week_key   int  not null,
  project    text not null check (project in ('orchard','watchtower','well')),
  chosen_at  timestamptz not null default now(),
  primary key (user_id, week_key)
);
alter table public.kingdom_projects enable row level security;
drop policy if exists "own projects read"   on public.kingdom_projects;
drop policy if exists "own projects insert" on public.kingdom_projects;
create policy "own projects read" on public.kingdom_projects
  for select using (user_id = auth.uid());
-- Choices are final for the week: no update or delete policy.
create policy "own projects insert" on public.kingdom_projects
  for insert with check (user_id = auth.uid());
revoke all on public.kingdom_projects from anon;
grant select, insert on public.kingdom_projects to authenticated;

-- Erase my data also removes project choices.
create or replace function public.delete_my_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  delete from public.pacts where user_id = me or partner_id = me;
  delete from public.pact_intents where from_id = me or to_id = me;
  delete from public.friendships where user_id = me or friend_id = me;
  update public.profiles set companion_id = null where user_id = me;
  delete from public.entries where user_id = me;        -- the audit trigger logs these deletions...
  delete from public.entries_audit where user_id = me;  -- ...and erasure then removes that history too
  delete from public.goals where user_id = me;
  delete from public.kingdom_projects where user_id = me;
  delete from public.pets where user_id = me;
  delete from public.creatures where user_id = me;
  delete from public.kingdoms where user_id = me;
  delete from public.profiles where user_id = me;
end $$;

revoke execute on function public.delete_my_data() from public, anon;
grant execute on function public.delete_my_data() to authenticated;
