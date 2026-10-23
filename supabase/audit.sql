-- Save Me: audit trail and data erasure.
-- Run once in Supabase → SQL Editor, AFTER habit.sql. Safe to run again.
--
-- Every change to a deposit or withdrawal (add, edit, delete) is recorded in entries_audit.
-- Nobody can edit or delete audit rows. Erasure (delete_my_data) is the one deliberate exception:
-- it removes a player's data and their audit history together. See PRIVACY.md.

create table if not exists public.entries_audit (
  id       bigint generated always as identity primary key,
  user_id  uuid not null,
  entry_id text not null,
  action   text not null check (action in ('insert','update','delete')),
  old_row  jsonb,
  new_row  jsonb,
  actor    uuid,
  at       timestamptz not null default now()
);
create index if not exists entries_audit_user_at on public.entries_audit (user_id, at);

create or replace function public.audit_entries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.entries_audit (user_id, entry_id, action, new_row, actor)
    values (new.user_id, new.id, 'insert', to_jsonb(new), auth.uid());
  elsif tg_op = 'UPDATE' then
    insert into public.entries_audit (user_id, entry_id, action, old_row, new_row, actor)
    values (new.user_id, new.id, 'update', to_jsonb(old), to_jsonb(new), auth.uid());
  else
    insert into public.entries_audit (user_id, entry_id, action, old_row, actor)
    values (old.user_id, old.id, 'delete', to_jsonb(old), auth.uid());
  end if;
  return null;
end $$;

drop trigger if exists entries_audit_trg on public.entries;
create trigger entries_audit_trg
  after insert or update or delete on public.entries
  for each row execute function public.audit_entries();

alter table public.entries_audit enable row level security;
drop policy if exists "own audit read" on public.entries_audit;
create policy "own audit read" on public.entries_audit for select to authenticated
  using (user_id = (select auth.uid()));

grant select on public.entries_audit to authenticated;
revoke all on public.entries_audit from anon;
revoke insert, update, delete on public.entries_audit from authenticated;

-- Erasure: removes everything the signed-in player has stored. Their login account stays;
-- deleting the login itself is done from the Supabase dashboard (Authentication → Users).
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
  delete from public.pets where user_id = me;
  delete from public.creatures where user_id = me;
  delete from public.kingdoms where user_id = me;
  delete from public.profiles where user_id = me;
end $$;

revoke execute on function public.delete_my_data() from public, anon;
grant execute on function public.delete_my_data() to authenticated;
