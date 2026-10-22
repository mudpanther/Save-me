-- Save Me: friends and leaderboard.
-- Run once in Supabase → SQL Editor, after schema.sql. Safe to run again.

create table if not exists public.profiles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 20),
  friend_code text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8)),
  created_at  timestamptz not null default now()
);

create table if not exists public.friendships (
  user_id    uuid not null references auth.users(id) on delete cascade,
  friend_id  uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

alter table public.profiles    enable row level security;
alter table public.friendships enable row level security;

drop policy if exists "own profile read"       on public.profiles;
drop policy if exists "own profile insert"     on public.profiles;
drop policy if exists "own profile update"     on public.profiles;
drop policy if exists "own friendships read"   on public.friendships;
create policy "own profile read"   on public.profiles for select to authenticated using (user_id = (select auth.uid()));
create policy "own profile insert" on public.profiles for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own profile update" on public.profiles for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own friendships read" on public.friendships for select to authenticated using (user_id = (select auth.uid()));

grant select, insert on public.profiles to authenticated;
grant update (name) on public.profiles to authenticated;
grant select on public.friendships to authenticated;
revoke all on public.profiles, public.friendships from anon;

-- Add a friend by their code. Both sides become friends at once.
create or replace function public.add_friend(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  other_id uuid;
  other_name text;
begin
  if me is null then raise exception 'Sign in first.'; end if;
  select user_id, name into other_id, other_name
    from public.profiles where friend_code = upper(trim(p_code));
  if other_id is null then raise exception 'No player has that code. Check it and try again.'; end if;
  if other_id = me then raise exception 'That is your own code.'; end if;
  insert into public.friendships (user_id, friend_id) values (me, other_id), (other_id, me)
    on conflict do nothing;
  return other_name;
end $$;

-- Remove a friend (both sides).
create or replace function public.remove_friend(p_friend uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.friendships
  where (user_id = auth.uid() and friend_id = p_friend)
     or (user_id = p_friend and friend_id = auth.uid());
$$;

-- The leaderboard: you plus your friends. Returns only name, streak, rarities and score.
-- Balances and amounts are never returned.
create or replace function public.friend_board()
returns table (player_id uuid, name text, is_me boolean, streak bigint, score bigint, creatures jsonb)
language sql
stable
security definer
set search_path = public
as $$
  with people as (
    select auth.uid() as uid
    union
    select friend_id from public.friendships where user_id = auth.uid()
  ),
  now_wk as (
    select ((floor(extract(epoch from now()) / 86400)::bigint + 3) / 7) as cw
  ),
  dep_weeks as (
    select distinct e.user_id as uid, ((e.t / 86400000) + 3) / 7 as wk
    from public.entries e
    where e.kind = 'deposit' and e.user_id in (select uid from people)
  ),
  ranked as (
    select uid, wk, row_number() over (partition by uid order by wk desc) as rn
    from dep_weeks
  ),
  runs as (
    select r.uid, count(*) as run_len
    from ranked r
    join ranked t on t.uid = r.uid and t.rn = 1
    where r.wk = t.wk - (r.rn - 1)
    group by r.uid
  ),
  streaks as (
    select p.uid,
           case when t.wk >= n.cw - 1 then coalesce(r.run_len, 0) else 0 end as streak
    from people p
    cross join now_wk n
    left join ranked t on t.uid = p.uid and t.rn = 1
    left join runs r on r.uid = p.uid
  ),
  creats as (
    select c.user_id as uid,
           jsonb_agg(jsonb_build_object('id', c.creature_id, 'r', c.rarity) order by c.creature_id) as list,
           sum(case c.rarity when 'common' then 1 when 'rare' then 3 when 'epic' then 6
                             when 'legendary' then 10 when 'mythic' then 15 else 0 end) as pts
    from public.creatures c
    where c.user_id in (select uid from people)
    group by c.user_id
  )
  select p.uid as player_id,
         pr.name as name,
         (p.uid = auth.uid()) as is_me,
         s.streak as streak,
         (coalesce(c.pts, 0) + 2 * s.streak) as score,
         coalesce(c.list, '[]'::jsonb) as creatures
  from people p
  join public.profiles pr on pr.user_id = p.uid
  join streaks s on s.uid = p.uid
  left join creats c on c.uid = p.uid
  order by score desc, pr.name;
$$;

revoke execute on function public.add_friend(text) from public, anon;
revoke execute on function public.remove_friend(uuid) from public, anon;
revoke execute on function public.friend_board() from public, anon;
grant execute on function public.add_friend(text) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.friend_board() to authenticated;
