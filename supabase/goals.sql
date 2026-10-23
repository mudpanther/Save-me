-- Savings places: named goals you are saving toward (nest egg, car, house...).
-- A goal is an allocation of your treasury, not a separate pot of money. Money is
-- never moved; the app fills goals in order from your balance.
-- Run after audit.sql. Adds no data and deletes nothing.

create table if not exists public.goals (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  kind       text not null check (kind in ('nest','emergency','car','house','other')),
  target     numeric(14,2) not null check (target > 0 and target <= 10000000),
  position   int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists goals_user_pos on public.goals (user_id, position);

alter table public.goals enable row level security;

drop policy if exists "own goals read"   on public.goals;
drop policy if exists "own goals insert" on public.goals;
drop policy if exists "own goals update" on public.goals;
drop policy if exists "own goals delete" on public.goals;

create policy "own goals read" on public.goals
  for select using (user_id = auth.uid());
-- At most 12 places per player, so the kingdom stays readable.
create policy "own goals insert" on public.goals
  for insert with check (
    user_id = auth.uid()
    and (select count(*) from public.goals g where g.user_id = auth.uid()) < 12
  );
create policy "own goals update" on public.goals
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own goals delete" on public.goals
  for delete using (user_id = auth.uid());

revoke all on public.goals from anon;
grant select, insert, update, delete on public.goals to authenticated;

-- Erase my data now includes savings places. Same behaviour as audit.sql, plus goals.
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
  delete from public.pets where user_id = me;
  delete from public.creatures where user_id = me;
  delete from public.kingdoms where user_id = me;
  delete from public.profiles where user_id = me;
end $$;

revoke execute on function public.delete_my_data() from public, anon;
grant execute on function public.delete_my_data() to authenticated;
