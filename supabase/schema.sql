-- Save Me database setup.
-- Paste this whole file into Supabase → SQL Editor → New query, then click Run.
-- It is safe to run more than once.

-- One row per player: the random seed that makes their creatures look unique.
create table if not exists public.kingdoms (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  seed       text not null check (char_length(seed) between 4 and 40),
  created_at timestamptz not null default now()
);

-- Every deposit, withdrawal and "set balance" entry.
create table if not exists public.entries (
  id         text primary key check (char_length(id) between 6 and 64),
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('deposit','withdraw','set')),
  amt        numeric(14,2) not null check (amt >= 0 and amt <= 100000000),
  note       text not null default '' check (char_length(note) <= 60),
  t          bigint not null,                      -- when it happened (ms since 1970)
  created_at timestamptz not null default now()
);
create index if not exists entries_user_t on public.entries (user_id, t);

-- Each creature's rarity, rolled once the first time it joins a kingdom.
create table if not exists public.creatures (
  user_id     uuid not null references auth.users(id) on delete cascade,
  creature_id text not null check (creature_id in ('dragon','phoenix','leviathan','wyrm','titan')),
  rarity      text not null check (rarity in ('common','rare','epic','legendary','mythic')),
  rolled_at   timestamptz not null default now(),
  primary key (user_id, creature_id)
);

-- Row-level security: every player can only ever see and change their own rows.
alter table public.kingdoms  enable row level security;
alter table public.entries   enable row level security;
alter table public.creatures enable row level security;

drop policy if exists "own kingdom read"   on public.kingdoms;
drop policy if exists "own kingdom insert" on public.kingdoms;
create policy "own kingdom read"   on public.kingdoms for select to authenticated using (user_id = (select auth.uid()));
create policy "own kingdom insert" on public.kingdoms for insert to authenticated with check (user_id = (select auth.uid()));
-- No update/delete policy: a kingdom's seed never changes, so your creatures keep their look.

drop policy if exists "own entries read"   on public.entries;
drop policy if exists "own entries insert" on public.entries;
drop policy if exists "own entries delete" on public.entries;
create policy "own entries read"   on public.entries for select to authenticated using (user_id = (select auth.uid()));
create policy "own entries insert" on public.entries for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own entries delete" on public.entries for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "own creatures read"   on public.creatures;
drop policy if exists "own creatures insert" on public.creatures;
create policy "own creatures read"   on public.creatures for select to authenticated using (user_id = (select auth.uid()));
create policy "own creatures insert" on public.creatures for insert to authenticated with check (user_id = (select auth.uid()));
-- No update policy: once a rarity is rolled it is permanent.

-- Let signed-in players reach these tables through the app (row-level security above still applies).
grant select, insert on public.kingdoms to authenticated;
grant select, insert, delete on public.entries to authenticated;
grant select, insert on public.creatures to authenticated;
revoke all on public.kingdoms, public.entries, public.creatures from anon;
