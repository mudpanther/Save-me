-- Save Me: habit progression, starter pet, and server-side checks for habit unlocks.
-- Run once in Supabase → SQL Editor, AFTER quests.sql (and pacts.sql). Safe to run again.
-- A habit week is any week where your deposits total at least $5. Habit weeks never reset.

-- Number of weeks with at least $5 saved, counted over your whole history.
create or replace function public.habit_weeks(p_uid uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from (
    select ((t / 86400000) + 3) / 7 as wk, sum(amt) as total
    from public.entries
    where user_id = p_uid and kind = 'deposit'
    group by 1
  ) w
  where w.total >= 5;
$$;

-- Starter pet: new players get a free pet at once, and it becomes their companion.
-- Players who already have their starter egg keep it.
create or replace function public.ensure_starter()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  pid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if exists (select 1 from public.pets where user_id = me and source = 'starter') then return; end if;
  insert into public.pets (user_id, kind, species, rarity, shiny, source, hatched_at)
  values (me, 'pet', 'ember_whelp', 'common', false, 'starter', now())
  returning id into pid;
  update public.profiles set companion_id = pid where user_id = me and companion_id is null;
end $$;

-- Creatures can unlock by balance OR by habit. The dragon also unlocks after 26 habit weeks.
create or replace function public.claim_creature(p_creature text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  v_need numeric;
  v_weeks int;
  st record;
  rar text;
begin
  if me is null then raise exception 'not signed in'; end if;

  select case p_creature
           when 'dragon' then 1000 when 'phoenix' then 10000 when 'leviathan' then 25000
           when 'wyrm' then 50000 when 'titan' then 100000 end,
         case p_creature when 'dragon' then 26 end
    into v_need, v_weeks;
  if v_need is null then raise exception 'unknown creature'; end if;

  select c.rarity into rar from public.creatures c where c.user_id = me and c.creature_id = p_creature;
  if rar is not null then return rar; end if;

  select * into st from public.ledger_state(me);
  if st.bal < v_need and not (v_weeks is not null and public.habit_weeks(me) >= v_weeks) then
    raise exception 'not yet';
  end if;

  rar := public.roll_rarity(st.streak);
  insert into public.creatures (user_id, creature_id, rarity) values (me, p_creature, rar)
  on conflict (user_id, creature_id) do nothing;

  select c.rarity into rar from public.creatures c where c.user_id = me and c.creature_id = p_creature;
  return rar;
end $$;

revoke execute on function public.habit_weeks(uuid)    from public, anon, authenticated;
revoke execute on function public.ensure_starter()     from public, anon;
revoke execute on function public.claim_creature(text) from public, anon;
grant execute on function public.ensure_starter()      to authenticated;
grant execute on function public.claim_creature(text)  to authenticated;
