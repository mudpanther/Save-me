# Save Me — Privacy notice (DRAFT)

> **Draft for qualified legal review before it is relied on.** This is a plain-language description of how the app works today. It is not legal advice, and it is not a finished privacy policy or terms of service.

## What Save Me is
Save Me is a game for tracking savings you already have. It does **not** connect to your bank, hold money, or move money. Every amount in the app is a number you enter yourself.

## What we store
- **Account:** your email address. Supabase stores your password in hashed form; the app never sees it in plain text.
- **Your savings records:** the deposits, withdrawals and balance you enter, with notes and dates.
- **Game progress:** your kingdom's random seed, creature rarities, pets, quest eggs and habit weeks.
- **Friends:** your display name and a friend code. Friends see your name, creature rarities and last check-in date. They never see your balances or your entries.
- **Pacts:** if you pair with a friend, each of you sees the other's last check-in date.
- **Audit history:** every change to a deposit or withdrawal is recorded, so corrections can be traced.

## What we never share
We do not sell your data. We do not show your balance or entries to other players. Leaderboards rank by game progress, not by money.

## Your choices
- **Download my data:** the Your data section of the History tab gives you a JSON file of everything stored for you.
- **Erase my data:** the same section deletes your entries, creatures, pets, friends, pacts and history. It cannot be undone. Your login account remains until you delete it in the Supabase dashboard.

## Where data lives
Data is stored in a Supabase project. The app itself is served from GitHub Pages as static files, which contain no personal data.

## Things that need qualified review before launch
- Which laws apply to the people using the app (for example, state consumer-protection and data-breach rules, and any rules for users under 18).
- Whether the audit history kept for corrections must be retained longer than erasure allows.
- Retention periods, data-processing agreements with Supabase, and cross-border transfer terms.
- Whether a financial-education disclaimer or any other statement is required.
- Terms of service.

## What this document does not claim
Save Me is not a bank, is not regulated as one, and has no certifications or regulatory approvals. Do not describe it to users as holding, insuring or protecting their money.
