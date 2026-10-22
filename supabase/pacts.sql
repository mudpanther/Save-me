-- Save Me: accountability pacts between friends.
-- Run once in Supabase → SQL Editor, AFTER friends.sql and quests.sql. Safe to run again.
-- A pact shares only names and the date of each partner's last check-in. Never balances.

-- Who has asked whom. A pact starts once both people have asked each other.
create table if not exists public.pact_intents (
  from_id    uuid not null references auth.users(id) on delete cascade,
  to_id      uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_id, to_id),
  check (from_id <> to_id)
);

-- Confirmed pacts. Each partner has one row pointing at the other.
create table if not exists public.pacts (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  partner_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (user_id <> partner_id)
);

alter table public.pact_intents enable row level security;
alter table public.pacts enable row level security;

drop policy if exists "own pact intents read" on public.pact_intents;
create policy "own pact intents read" on public.pact_intents for select to authenticated
  using (from_id = (select auth.uid()) or to_id = (select auth.uid()));

drop policy if exists "own pact read" on public.pacts;
create policy "own pact read" on public.pacts for select to authenticated
  using (user_id = (select auth.uid()));

grant select on public.pact_intents, public.pacts to authenticated;
revoke all on public.pact_intents, public.pacts from anon;

-- Ask a friend for a pact. If they already asked you, the pact starts now.
create or replace function public.propose_pact(p_friend uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from public.friendships where user_id = me and friend_id = p_friend) then
    raise exception 'you can only pair with friends';
  end if;
  if exists (select 1 from public.pacts where user_id = me) then raise exception 'you already have a pact'; end if;
  if exists (select 1 from public.pacts where user_id = p_friend) then raise exception 'they already have a pact'; end if;

  if exists (select 1 from public.pact_intents where from_id = p_friend and to_id = me) then
    delete from public.pact_intents where (from_id = p_friend and to_id = me) or (from_id = me and to_id = p_friend);
    insert into public.pacts (user_id, partner_id) values (me, p_friend), (p_friend, me);
    return 'paired';
  end if;

  insert into public.pact_intents (from_id, to_id) values (me, p_friend) on conflict do nothing;
  return 'proposed';
end $$;

-- Ends your pact and withdraws any requests you've made or received.
create or replace function public.end_pact()
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
end $$;

-- Everything the pact screen needs: your partner, when they last checked in, and requests either way.
create or replace function public.pact_status()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  partner uuid;
  result json;
begin
  if me is null then raise exception 'not signed in'; end if;
  select partner_id into partner from public.pacts where user_id = me;
  result := json_build_object(
    'partner', (select json_build_object('id', pr.user_id, 'name', pr.name)
                  from public.profiles pr where pr.user_id = partner),
    'partner_last_checkin', (select max(e.t) from public.entries e where e.user_id = partner),
    'incoming', coalesce((select json_agg(json_build_object('id', pr.user_id, 'name', pr.name))
                  from public.pact_intents i join public.profiles pr on pr.user_id = i.from_id
                  where i.to_id = me), '[]'::json),
    'outgoing', coalesce((select json_agg(i.to_id) from public.pact_intents i where i.from_id = me), '[]'::json)
  );
  return result;
end $$;

revoke execute on function public.propose_pact(uuid) from public, anon;
revoke execute on function public.end_pact()         from public, anon;
revoke execute on function public.pact_status()      from public, anon;
grant execute on function public.propose_pact(uuid) to authenticated;
grant execute on function public.end_pact()          to authenticated;
grant execute on function public.pact_status()       to authenticated;
