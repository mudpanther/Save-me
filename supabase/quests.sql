-- Save Me: eggs, pets, weekly quests, companions, and server-side rolls.
-- Run once in Supabase → SQL Editor, AFTER schema.sql and friends.sql. Safe to run again.
-- Every roll (creature rarity, egg hatch, shiny) happens on the server, so the app can't pick its own loot.

-- ---------- tables ----------

-- Eggs and pets. An egg hatches into a pet once its deposits reach `need`.
create table if not exists public.pets (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('egg','pet')),
  egg_tier   text check (egg_tier in ('small','big','rare')),
  need       numeric(14,2) check (need is null or need > 0),  -- dollars to deposit before it hatches
  source     text,                                              -- 'starter' or 'quest:<key>:<week>', one per player
  species    text check (species in ('ember_whelp','frost_drake','glimmer_hawk','storm_wren',
                                     'lantern_sprite','tide_eel','sand_wyrmling','star_koi')),
  rarity     text check (rarity in ('common','rare','epic','legendary','mythic')),
  shiny      boolean not null default false,
  created_at timestamptz not null default now(),
  hatched_at timestamptz,
  unique (user_id, source),
  check (
    (kind = 'egg' and egg_tier is not null and need is not null)
    or (kind = 'pet' and species is not null and rarity is not null)
  )
);

alter table public.profiles add column if not exists companion_id uuid references public.pets(id) on delete set null;

-- ---------- row-level security ----------

alter table public.pets enable row level security;

-- Players can read their own pets. Nobody writes them directly: only the functions below do.
drop policy if exists "own pets read"   on public.pets;
drop policy if exists "own pets insert" on public.pets;
drop policy if exists "own pets update" on public.pets;
create policy "own pets read" on public.pets for select to authenticated using (user_id = (select auth.uid()));

grant select on public.pets to authenticated;
revoke insert, update, delete on public.pets from authenticated;
revoke all on public.pets from anon;

-- Creatures are rolled by claim_creature() only, so the direct insert path goes away.
drop policy if exists "own creatures insert" on public.creatures;
revoke insert on public.creatures from authenticated;

-- A companion is chosen with set_companion(), not a direct update.
revoke update (companion_id) on public.profiles from authenticated;
revoke update (companion_id) on public.profiles from anon;

-- ---------- helpers (internal) ----------

-- Current balance and streak, worked out the same way the app does it.
create or replace function public.ledger_state(p_uid uuid)
returns table (bal numeric, streak int)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rec record;
  b numeric := 0;
  prev numeric;
  weeks bigint[] := '{}';
  w bigint;
  s int := 0;
begin
  for rec in select kind, amt, t from public.entries where user_id = p_uid order by t loop
    prev := b;
    if rec.kind = 'deposit' then b := b + rec.amt;
    elsif rec.kind = 'withdraw' then b := greatest(0, b - rec.amt);
    else b := rec.amt;
    end if;
    if b > prev then weeks := array_append(weeks, ((rec.t / 86400000) + 3) / 7); end if;
  end loop;
  w := (floor(extract(epoch from now()) / 86400)::bigint + 3) / 7;
  if not (w = any(weeks)) then w := w - 1; end if;
  while w = any(weeks) loop
    s := s + 1;
    w := w - 1;
  end loop;
  return query select b, least(s, 8);
end $$;

-- Same odds as the app's old client roll: a streak of up to 8 weeks improves the rarity.
create or replace function public.roll_rarity(p_streak int)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r double precision := random();
  luck double precision := least(8, greatest(0, p_streak)) * 0.1;
begin
  r := 1 - power(1 - r, 1 + luck);
  return case when r >= 0.98 then 'mythic'
              when r >= 0.90 then 'legendary'
              when r >= 0.75 then 'epic'
              when r >= 0.45 then 'rare'
              else 'common' end;
end $$;

-- ---------- player actions ----------

-- Gives every player one starter egg. Safe to call again.
create or replace function public.ensure_starter()
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.pets (user_id, kind, egg_tier, need, source)
  values (auth.uid(), 'egg', 'small', 100, 'starter')
  on conflict (user_id, source) do nothing;
$$;

-- Claims a finished weekly quest and drops its egg. Each quest can be claimed once a week.
create or replace function public.claim_quest(p_key text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  wk bigint := (floor(extract(epoch from now()) / 86400)::bigint + 3) / 7;
  dep_count int;
  dep_sum numeric;
  wd_count int;
  tier text;
  v_need numeric;
  src text;
  ok boolean;
begin
  if me is null then raise exception 'not signed in'; end if;

  select count(*) filter (where kind = 'deposit'),
         coalesce(sum(amt) filter (where kind = 'deposit'), 0),
         count(*) filter (where kind = 'withdraw')
    into dep_count, dep_sum, wd_count
    from public.entries
   where user_id = me and ((t / 86400000) + 3) / 7 = wk;

  case p_key
    when 'deposit3'   then ok := dep_count >= 3;                  tier := 'small';
    when 'save100'    then ok := dep_sum >= 100;                  tier := 'big';
    when 'nowithdraw' then ok := dep_count >= 1 and wd_count = 0; tier := 'small';
    else raise exception 'unknown quest';
  end case;
  if not ok then raise exception 'quest not finished'; end if;

  v_need := case tier when 'small' then 100 else 500 end;
  src := 'quest:' || p_key || ':' || wk;
  insert into public.pets (user_id, kind, egg_tier, need, source)
  values (me, 'egg', tier, v_need, src)
  on conflict (user_id, source) do nothing;
  return src;
end $$;

-- Hatches an egg once its deposits since it was laid reach its amount. Species, rarity and shiny are rolled here.
create or replace function public.hatch_egg(p_egg uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  egg record;
  prog numeric;
  st record;
  species_list text[] := array['ember_whelp','frost_drake','glimmer_hawk','storm_wren',
                               'lantern_sprite','tide_eel','sand_wyrmling','star_koi'];
  sp text;
  rar text;
  sh boolean;
begin
  if me is null then raise exception 'not signed in'; end if;

  select * into egg from public.pets where id = p_egg and user_id = me and kind = 'egg' for update;
  if not found then raise exception 'no such egg'; end if;

  select coalesce(sum(amt), 0) into prog from public.entries
   where user_id = me and kind = 'deposit' and t >= extract(epoch from egg.created_at) * 1000;
  if prog < egg.need then raise exception 'egg not ready'; end if;

  select * into st from public.ledger_state(me);
  sp := species_list[1 + floor(random() * array_length(species_list, 1))::int];
  rar := public.roll_rarity(st.streak);
  sh := random() < 0.02;

  update public.pets
     set kind = 'pet', species = sp, rarity = rar, shiny = sh, hatched_at = now()
   where id = egg.id;

  return json_build_object('id', egg.id, 'species', sp, 'rarity', rar, 'shiny', sh);
end $$;

-- Rolls a creature's rarity once, the first time the player reaches its unlock amount.
create or replace function public.claim_creature(p_creature text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  v_need numeric;
  st record;
  rar text;
begin
  if me is null then raise exception 'not signed in'; end if;

  v_need := case p_creature
    when 'dragon' then 1000 when 'phoenix' then 10000 when 'leviathan' then 25000
    when 'wyrm' then 50000 when 'titan' then 100000 else null end;
  if v_need is null then raise exception 'unknown creature'; end if;

  select c.rarity into rar from public.creatures c where c.user_id = me and c.creature_id = p_creature;
  if rar is not null then return rar; end if;

  select * into st from public.ledger_state(me);
  if st.bal < v_need then raise exception 'not yet'; end if;

  rar := public.roll_rarity(st.streak);
  insert into public.creatures (user_id, creature_id, rarity) values (me, p_creature, rar)
  on conflict (user_id, creature_id) do nothing;

  select c.rarity into rar from public.creatures c where c.user_id = me and c.creature_id = p_creature;
  return rar;
end $$;

-- Picks which pet flies over your kingdom (null to clear it).
create or replace function public.set_companion(p_pet uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_pet is not null and not exists (
       select 1 from public.pets where id = p_pet and user_id = me and kind = 'pet') then
    raise exception 'not your pet';
  end if;
  update public.profiles set companion_id = p_pet where user_id = me;
  if not found then raise exception 'no profile yet'; end if;
end $$;

-- ---------- leaderboard (now counts pets too; still returns only names, streaks, rarities and scores) ----------

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
  ),
  pet_items as (
    select x.user_id as uid,
           jsonb_agg(jsonb_build_object('id', x.species, 'r', x.rarity, 's', x.shiny) order by x.species) as list,
           sum(case x.rarity when 'common' then 1 when 'rare' then 3 when 'epic' then 6
                             when 'legendary' then 10 when 'mythic' then 15 else 0 end) as pts
    from public.pets x
    where x.kind = 'pet' and x.user_id in (select uid from people)
    group by x.user_id
  )
  select p.uid as player_id,
         pr.name as name,
         (p.uid = auth.uid()) as is_me,
         s.streak as streak,
         (coalesce(c.pts, 0) + coalesce(pi.pts, 0) + 2 * s.streak) as score,
         (coalesce(c.list, '[]'::jsonb) || coalesce(pi.list, '[]'::jsonb)) as creatures
  from people p
  join public.profiles pr on pr.user_id = p.uid
  join streaks s on s.uid = p.uid
  left join creats c on c.uid = p.uid
  left join pet_items pi on pi.uid = p.uid
  order by score desc, pr.name;
$$;

-- ---------- permissions: only the functions above can change loot, eggs or companions ----------

revoke execute on function public.ledger_state(uuid)   from public, anon, authenticated;
revoke execute on function public.roll_rarity(int)     from public, anon, authenticated;

revoke execute on function public.ensure_starter()     from public, anon;
revoke execute on function public.claim_quest(text)    from public, anon;
revoke execute on function public.hatch_egg(uuid)      from public, anon;
revoke execute on function public.claim_creature(text) from public, anon;
revoke execute on function public.set_companion(uuid)  from public, anon;
revoke execute on function public.friend_board()       from public, anon;

grant execute on function public.ensure_starter()      to authenticated;
grant execute on function public.claim_quest(text)     to authenticated;
grant execute on function public.hatch_egg(uuid)       to authenticated;
grant execute on function public.claim_creature(text)  to authenticated;
grant execute on function public.set_companion(uuid)   to authenticated;
grant execute on function public.friend_board()        to authenticated;
