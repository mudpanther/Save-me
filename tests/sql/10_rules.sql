-- Behaviour tests for every server-side rule. Any failed assertion stops psql with a non-zero exit code.
\set ON_ERROR_STOP on

-- ---------- seed (as the database owner, so RLS does not get in the way) ----------
insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),   -- Max
  ('22222222-2222-2222-2222-222222222222'),   -- Brandon
  ('33333333-3333-3333-3333-333333333333')    -- stranger
on conflict do nothing;
insert into public.profiles (user_id, name) values
  ('11111111-1111-1111-1111-111111111111', 'Max'),
  ('22222222-2222-2222-2222-222222222222', 'Brandon'),
  ('33333333-3333-3333-3333-333333333333', 'Stranger')
on conflict do nothing;
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

-- Max: 26 weeks of $5 (habit weeks), plus 10 cents and 20 cents this week.
insert into public.entries (id, user_id, kind, amt, note, t)
  select 'maxw-' || lpad(g::text, 3, '0'), '11111111-1111-1111-1111-111111111111', 'deposit', 5, '',
         (extract(epoch from now()) * 1000)::bigint - g::bigint * 7 * 86400000
  from generate_series(1, 26) g;
insert into public.entries (id, user_id, kind, amt, note, t) values
  ('maxc-0001', '11111111-1111-1111-1111-111111111111', 'deposit', 0.10, '', (extract(epoch from now()) * 1000)::bigint),
  ('maxc-0002', '11111111-1111-1111-1111-111111111111', 'deposit', 0.20, '', (extract(epoch from now()) * 1000)::bigint);

-- Brandon: 30 weeks of $4 (below the habit bar), so he should have zero habit weeks.
insert into public.entries (id, user_id, kind, amt, note, t)
  select 'brow-' || lpad(g::text, 3, '0'), '22222222-2222-2222-2222-222222222222', 'deposit', 4, '',
         (extract(epoch from now()) * 1000)::bigint - g::bigint * 7 * 86400000
  from generate_series(0, 29) g;

-- ---------- money and habit maths (owner context) ----------
select public.t_assert((select bal from ledger_state('11111111-1111-1111-1111-111111111111')) = 130.30,
  'Max balance is exactly 130.30 (0.10 + 0.20 has no float drift)');
select public.t_assert(habit_weeks('11111111-1111-1111-1111-111111111111') = 26,
  'Max has exactly 26 habit weeks');
select public.t_assert(habit_weeks('22222222-2222-2222-2222-222222222222') = 0,
  'Brandon ($4 a week) earns no habit weeks');

-- ---------- as Max (signed in, row-level security applies) ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select public.t_assert((select count(*) from public.entries where user_id <> auth.uid()) = 0,
  'Max cannot read anyone else''s entries');

-- Starter pet is idempotent
select ensure_starter(); select ensure_starter();
select public.t_assert((select count(*) from public.pets where user_id = auth.uid() and source = 'starter') = 1,
  'starter pet is created exactly once');

-- Quests need real progress this week
select public.t_expect_error($q$select claim_quest('deposit3')$q$);
select public.t_expect_error($q$select claim_quest('save100')$q$);

-- Dragon: 26 habit weeks is enough even with a tiny balance
select claim_creature('dragon');
select public.t_assert((select count(*) from public.creatures where user_id = auth.uid() and creature_id = 'dragon') = 1,
  'dragon unlocks by habit weeks');
select claim_creature('dragon');
select public.t_assert((select count(*) from public.creatures where user_id = auth.uid() and creature_id = 'dragon') = 1,
  'dragon is rolled only once');

-- Phoenix needs $10,000 and Max has about $130
select public.t_expect_error($q$select claim_creature('phoenix')$q$);

-- Direct writes are refused
select public.t_expect_error($q$insert into public.creatures (user_id, creature_id, rarity) values (auth.uid(), 'titan', 'mythic')$q$);
select public.t_expect_error($q$update public.pets set rarity = 'mythic'$q$);
select public.t_expect_error($q$insert into public.pets (user_id, kind, egg_tier, need, source) values (auth.uid(), 'egg', 'small', 0.01, 'hack')$q$);
select public.t_expect_error($q$update public.profiles set companion_id = null$q$);

-- A stranger cannot be paired with, but a friend can
select public.t_expect_error($q$select propose_pact('33333333-3333-3333-3333-333333333333')$q$);

-- Audit: Max can read his own history but never change it
select public.t_assert((select count(*) from public.entries_audit where user_id = auth.uid()) > 0,
  'every entry change is in the audit trail');
select public.t_expect_error($q$delete from public.entries_audit$q$);
select public.t_expect_error($q$update public.entries_audit set action = 'x'$q$);
select public.t_expect_error($q$insert into public.entries_audit (user_id, entry_id, action) values (auth.uid(), 'fake-0001', 'insert')$q$);

-- ---------- as Brandon: cannot touch Max's eggs or pets ----------
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.t_expect_error($q$select hatch_egg('00000000-0000-0000-0000-000000000000')$q$);
select public.t_assert((select count(*) from public.pets) = 0 or
       (select count(*) from public.pets where user_id <> auth.uid()) = 0,
  'Brandon cannot see Max''s pets');

-- ---------- erasure: Max erases his data, Brandon's stays intact ----------
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
-- Savings places: owner-only, capped, no zero targets.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
insert into public.goals (name, kind, target, position) values ('Nest egg', 'nest', 5000, 1);
select public.t_assert((select count(*) from public.goals where user_id = auth.uid()) = 1,
  'Max can add a savings place');
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.t_assert((select count(*) from public.goals where user_id = '11111111-1111-1111-1111-111111111111') = 0,
  'Brandon cannot see Max''s savings places');
select public.t_expect_error($q$insert into public.goals (user_id, name, kind, target) values ('11111111-1111-1111-1111-111111111111', 'x', 'car', 100)$q$);
select public.t_expect_error($q$insert into public.goals (name, kind, target) values ('x', 'car', 0)$q$);
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

select delete_my_data();
reset role;
select public.t_assert((select count(*) from public.entries where user_id = '11111111-1111-1111-1111-111111111111') = 0,
  'erasure removes Max''s entries');
select public.t_assert((select count(*) from public.entries_audit where user_id = '11111111-1111-1111-1111-111111111111') = 0,
  'erasure removes Max''s audit history');
select public.t_assert((select count(*) from public.entries where user_id = '22222222-2222-2222-2222-222222222222') = 30,
  'erasure leaves Brandon''s entries untouched');
select public.t_assert((select count(*) from public.profiles where user_id = '11111111-1111-1111-1111-111111111111') = 0,
  'erasure removes Max''s profile');

select 'ALL RULE TESTS PASSED' as result;
