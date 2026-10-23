# Save Me

Save money. Save the kingdom.

A pixel-art fantasy kingdom that grows with your real savings. Log deposits and your castle, army and creatures grow. Withdraw and they leave. Your money never leaves your bank; the app only tracks it.

- 14 buildings and 5 creatures (dragon, phoenix, leviathan, celestial wyrm, world titan), each with upgrade stages
- Weekly quests drop eggs. Deposit into an egg to hatch a pet, and pick one to fly over your kingdom
- Every creature's rarity is rolled once when it first arrives, and its look is generated just for your kingdom
- Weekly deposit streaks improve rarity odds
- Cloud saves through Supabase, so progress follows you between devices
- Installs to your phone's home screen and opens offline

---

## Setup (about 15 minutes, all free)

### 1. Create the database (Supabase)

1. Go to [supabase.com](https://supabase.com), sign up, and click **New project**.
2. Name it `save-me`, set a database password (save it somewhere), pick the region closest to you (East US), and create it. It takes a minute or two to start.
3. In the left sidebar open **SQL Editor**, then run these six files one at a time, in this order. For each: click **New query** (or **Raw** on GitHub to copy the file), paste it in, and click **Run**. Warnings about "destructive operations" are expected, since the files replace older policies.
   1. `supabase/schema.sql`
   2. `supabase/friends.sql`
   3. `supabase/quests.sql`
   4. `supabase/pacts.sql`
   5. `supabase/habit.sql`
   6. `supabase/audit.sql`
4. Open **Authentication → Sign In / Providers** and make sure **Email** is turned on (it is by default).
   - Easiest option: turn **Confirm email** off. People can sign up and start playing right away.
   - If you leave it on, new players get a confirmation email first. In that case also do step 3 of Part 3 below.
5. Click **Connect** at the top of the project (or go to **Project Settings → API Keys**) and copy two things:
   - the **Project URL** (looks like `https://abcdefghijkl.supabase.co`)
   - the **anon public** key or the **publishable** key

Never copy the `service_role` or secret key into the app. That key bypasses all the privacy rules.

### 2. Connect the app

Open `config.js` and paste your two values in place of the placeholders:

```js
window.SAVE_ME_CONFIG = {
  url: "https://abcdefghijkl.supabase.co",
  anonKey: "eyJhbGciOi..."
};
```

The anon/publishable key is designed to be public, so it's fine for it to be in a public GitHub repo. The row-level security rules in `schema.sql` are what keep each person's kingdom private: every player can only read and write their own rows.

### 3. Publish it (GitHub Pages)

1. On GitHub, create a new **public** repository named `save-me`.
2. Upload all the files in this folder, keeping the folder structure (`icons/`, `vendor/`, `supabase/`).
3. In the repo go to **Settings → Pages**. Under **Build and deployment**, choose **Deploy from a branch**, branch **main**, folder **/ (root)**, then **Save**.
4. After a minute your app is live at `https://mudpanther.github.io/save-me/`.
5. If you kept **Confirm email** on: in Supabase go to **Authentication → URL Configuration** and set **Site URL** to that GitHub Pages address, so confirmation links bring people back to the app.

### 4. Put it on your phone

- **Android (Chrome):** open your link, tap **⋮ → Install app** (or the **Install app** button at the top of the page). It gets its own icon and opens full-screen.
- **iPhone (Safari):** open your link, tap **Share → Add to Home Screen**.

Create your account, use **Set balance** to enter what's in savings right now, then log each deposit as you make it.

---

## Sharing with friends

Send them the link. Each person taps **Create account** and gets their own empty kingdom with their own seed, so their creatures look different from yours. Nobody can see anyone else's balance.

## Updating the app

When you change any file, also open `sw.js` and bump the version (for example `save-me-v1` to `save-me-v2`). That tells installed phones to fetch the new version. Closing and reopening the app twice picks it up.

## Good to know

- **Free Supabase projects pause after about a week with no activity.** Opening the app counts as activity, so regular use keeps it awake. If it ever pauses, open the Supabase dashboard and click **Restore**. Your data is kept.
- **Offline:** the app opens without internet and shows your last save. Entries you log offline are queued and upload automatically when you reconnect.
- **Rarity is permanent and server-rolled.** Creatures, eggs and pets are rolled by the database, not the app, so nobody can pick a rarity for themselves.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole game: kingdom scene, creatures, treasury, ledger, sign-in |
| `config.js` | Your Supabase URL and public key |
| `manifest.webmanifest` | App name, icon and colors for installing on a phone |
| `sw.js` | Service worker that lets the app open offline |
| `vendor/supabase.js` | Supabase client library (v2.45.4, MIT license) |
| `icons/` | App icons |
| `supabase/schema.sql` | Database tables and privacy rules |
| `supabase/friends.sql` | Friends, friend codes and the leaderboard |
| `supabase/quests.sql` | Eggs, pets, weekly quests, companions, and the server-side rolls |
| `supabase/pacts.sql` | Accountability pacts between friends |
| `supabase/habit.sql` | Habit weeks, the starter pet, and habit-based unlocks |
| `supabase/audit.sql` | Audit trail for deposits and withdrawals, and erase-my-data |
| `tests/sql/` | Database rule tests, run in CI and locally with `tests/sql/run.sh` |
| `PRIVACY.md` | Privacy notice draft (needs qualified legal review) |
| `PROGRESS.md` | What is finished, what is tested, and what is still open |

## Testing

- **Database rules:** `tests/sql/run.sh` builds a fresh Postgres 16 database, loads every SQL file in order, and runs `tests/sql/10_rules.sql`. The run stops with a non-zero exit code on the first failed assertion. CI runs it on every push.
- **Browser script:** CI checks that the app's JavaScript parses. Screen-level checks were run by hand in a headless browser; they are not automated yet.
- The test stub in `tests/sql/00_stub.sql` stands in for Supabase's login system. It is never loaded into a real project.

## Your data

Players can download everything Save Me stores for them, or erase it, from the **History → Your data** section. See `PRIVACY.md` for the draft notice.

