# Save Me — progress

Last updated: 2026-10-22. Source of truth is this repo (`main`). Live site: https://mudpanther.github.io/Save-me/

## Done and live (on GitHub Pages once deployed)
- **Kingdom:** pixel scene drawn at whole-number scale, paused on other tabs, about 30 fps. Tap a creature or companion for a close-up card.
- **Central building grows** with savings: hut, stone house, manor, keep, castle, palace, then four endgame tiers up to the Mythic Throne at $1,000,000.
- **Habit progression:** a week with at least $5 saved counts once; habit weeks never reset. Buildings and house upgrades unlock by balance or habit. The dragon unlocks at $1,000 or 26 habit weeks.
- **Creatures, eggs and pets are rolled on the server** (`claim_creature`, `hatch_egg`, `claim_quest`). The app cannot choose a rarity.
- **Eggs, weekly quests, companion pets, and a starter pet** for new players.
- **Friends and leaderboard:** friend codes, leaderboard by collection and streak. Balances are never shared.
- **Accountability pacts:** pair with a friend once both ask. Each sees the other's last check-in date only.
- **Four tabs:** Kingdom, Quests, Friends, History.
- **Money in whole cents** in the app (balances, lifetime, eggs, week totals). Stored as `numeric(14,2)` in the database.
- **Monthly summary** in History: saved, withdrawn and balance at month end, from your own entries.
- **Download my data** (History → Your data): JSON of your profile, kingdom seed, entries, audit history, pets, creatures and pacts.
- **First-run welcome card** on the Kingdom tab, dismissed with "Got it" and remembered on that device.

## Written but NOT yet run in Supabase
- `supabase/goals.sql`: **savings places** (nest egg, emergency fund, car, house, custom). Goals are allocations of your treasury filled in order; no money moves. Run after `audit.sql`. Until it runs, the places section stays empty and the rest of the app still works.
- `supabase/audit.sql`: audit trail for every deposit/withdrawal change, and `delete_my_data()` used by **Erase my data**. **Until this runs, Erase my data will show an error and nothing is deleted.** Run it after `habit.sql`.

## Database files (run in Supabase SQL Editor, in this order)
1. `supabase/schema.sql`
2. `supabase/friends.sql`
3. `supabase/quests.sql`
4. `supabase/pacts.sql`
5. `supabase/habit.sql`
6. `supabase/audit.sql`
7. `supabase/goals.sql`

## Tested
- **SQL rule tests** (`tests/sql/run.sh`, `tests/sql/10_rules.sql`): exact cents balance, habit-week counting, starter pet idempotence, quest gating, creature rolls once, dragon by habit, phoenix refused at low balance, direct writes blocked on creatures/pets/profiles, pacts refuse strangers, audit trail present and append-only, cross-user isolation, erasure removes one player's data and not another's. Verified that a deliberately false assertion makes the run exit non-zero.
- **Browser (headless Chromium, phone width):** tab switching, scene layout, tap-to-inspect, habit unlocks, pact screen, welcome card, monthly summary arithmetic, data panel buttons, no page errors.
- **CI** (`.github/workflows/ci.yml`): JavaScript parse of the app script, service worker and config, plus the SQL suite on Postgres 16, on every push.

## Not tested
- A live Supabase project (the build sandbox cannot reach one). The first real run of each SQL file is the test.
- Real phones (Android and iPhone), install prompts, offline behaviour, and service-worker updates on an installed app.
- Export and erase buttons in a real signed-in session (the server side is tested; the button wiring is not).
- Accessibility audit (screen readers, keyboard-only use, contrast measurements).
- Performance on mid-range Android hardware. Frame rate was measured in a desktop headless browser only.

## Not built yet (from the product directive) and why
- **Onboarding flow** that asks goal, pace and kingdom name. Only the welcome card exists. The full flow is the next most valuable item.
- **Multiple named savings goals** with target dates and suggested contributions.
- **Savings plans** (weekly, biweekly, monthly income schedules) and reminders. Planned as expected contributions, never as real transfers.
- **XP and levels**, creature journals and biographies, collection-completion rewards, shiny and cosmetic evolution.
- **Quest variety** beyond the three weekly quests (budgeting challenges, emergency-fund milestones, seasonal events).
- **Sound, haptics, and a reduced-motion switch** in settings. Motion is already calmer and reduced-motion is respected by the existing code, but there is no user switch.
- **Push notifications and reminders.** Needs push permissions plus a server job. Not built.
- **Analytics.** Not started. Needs a consent decision before any tracking.
- **Monetization.** Not started and deliberately so. No payment processing, no subscriptions, no paid streak protection.
- **Banking integration.** Not started and not authorized. The app only tracks balances the user enters.
- **Automated browser tests.** Screen checks were done by hand with a headless browser; they are not in CI yet.
- **Legal review** of `PRIVACY.md` and terms of service. Draft only.

## Security and reliability notes (known, not yet fixed)
- **Erase leaves the login account.** Deleting the sign-in itself is a manual step in the Supabase dashboard.
- **Audit history and erasure conflict by design.** Erasure removes a player's audit history too. This is a policy choice for legal review (see PRIVACY.md).
- **Friend codes have no rate limit.** A determined person could guess codes and send friend requests. Friends see only a name, rarities and streak. Consider rate limiting or requiring acceptance before the next release.
- **Supabase's default rate limits apply** to sign-up and sign-in. No custom limits are set.
- **The publishable key is in `config.js`.** That is expected for a public key; row-level security is what protects data. Never add the secret or service-role key to this repo.
- **Offline queue.** Deposits made offline are queued on the phone and sent on reconnect. A duplicate send is safe because entries use client-generated IDs and inserts ignore duplicates, but the queue has not been tested on a real flaky connection.

## Assumptions (reversible)
- A habit week is a calendar week (Monday start) with at least $5 of deposits.
- Habit weeks never reset, so breaking a streak does not lose them.
- Unlock amounts for the $300k–$1M tiers are my picks and can be tuned.
- Erasure removes audit history for that player. Revisit after legal review.

## Next steps, in order
1. Run `supabase/audit.sql` in Supabase. Then test Download my data and Erase my data on a throwaway account before using it on a real one.
2. Confirm CI passes on the first push (Actions tab on GitHub).
3. Build the onboarding flow (goal, pace, kingdom name), then multiple goals.
4. Real-phone test on Android and iPhone, including install and update.
5. Friend-code rate limiting and an accept step for friend requests.

## Motivation notes (research, Oct 2026)
Why these choices, and what to watch so the app motivates without manipulating:
- **Commitment works.** In a Philippines study (J-PAL, SEED accounts), savers who could set a goal and were blocked from withdrawing until they reached it grew balances 42% after six months and 82% after a year. Savings outside the bank did not fall. Save Me cannot lock real money, so this is a future option (for example, a pledge that asks for a confirmation before a withdrawal), not built.
- **Visible progress helps.** The goal-gradient effect says effort rises as a goal gets closer. The strongest evidence is from animals; human evidence is thinner. Treat progress bars as useful, not proven.
- **Guilt backfires.** Streak-loss messages can push people to quit after one miss. The daily lamp is deliberately non-punitive: dark means "not yet today", never "you failed".
- **Shown, not shamed.** A withdrawal is logged as a plain line in the chronicle, with no judgement.

Built from these notes: savings places (cards and plots in the scene, up to four), the chronicle, and the daily lamp.
Still to build from the list: creature backstories, choices about what the kingdom works on next, and a stone-loss view for withdrawals. Scene plots are small (about 12 pixels) and sit at the edges; they need a real-phone look before we tune them.
