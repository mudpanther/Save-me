# Save Me — progress

## Done (live on GitHub Pages)
- Kingdom scene: growing central building (hut → stone house → manor → keep → castle → palace → sunspire → crystal → empire → mythic throne at $1M), balance-driven.
- Habit progression: a week with $5+ saved counts once. Buildings and house upgrades unlock by balance OR habit weeks. Dragon unlocks at $1,000 or 26 habit weeks.
- Creatures and pets rolled on the server (claim_creature, hatch_egg, claim_quest). Client cannot choose rarity.
- Eggs, weekly quests, companion pets, starter pet (new players).
- Friends leaderboard, accountability pacts (names and last check-in only, never balances).
- Four tabs (Kingdom, Quests, Friends, History). Tap-to-inspect creature cards.
- Crisp integer-scaled scene, paused on other tabs, about 30 fps.

## Database files (run in Supabase SQL Editor, in order)
1. supabase/schema.sql
2. supabase/friends.sql
3. supabase/quests.sql
4. supabase/pacts.sql
5. supabase/habit.sql

## Tested
- SQL: each file loads on a local Postgres 16 with a stand-in auth schema. Behaviour tests cover quests, hatching gates, creature rolls, direct-write blocks, pacts, and habit weeks.
- Client: headless Chromium at phone width. Checks cover tab switching, scene layout, tap-to-inspect, habit unlocks, and the pact screen.
- Not tested: a live Supabase project (the test sandbox cannot reach it), real phones, and push notifications (not built).

## Not started (from the product directive)
- Decimal money in the ledger (amounts are numeric in SQL; client still uses floats for display maths).
- Audit history for corrections; export; data deletion flow.
- Multiple named savings goals; onboarding flow; financial dashboard.
- Push notifications and reminders.
- Automated CI, production analytics, privacy policy and terms (need legal review).

## Assumptions
- A habit week is a calendar week (Monday start) with at least $5 of deposits.
- Habit weeks never reset, so breaking a streak does not lose them.
- Unlock amounts for the new tiers ($300k–$1M) are my picks and can be tuned.
