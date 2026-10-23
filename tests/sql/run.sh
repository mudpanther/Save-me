#!/usr/bin/env bash
# Builds a fresh database, loads the app's SQL in order, then runs the rule tests.
# Usage: PGHOST=127.0.0.1 PGPORT=5433 PGUSER=postgres tests/sql/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${PGDATABASE:-savemetest}"
P=(psql -X -v ON_ERROR_STOP=1 -q)
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
for f in tests/sql/00_stub.sql supabase/schema.sql supabase/friends.sql supabase/quests.sql \
         supabase/pacts.sql supabase/habit.sql supabase/audit.sql supabase/goals.sql "${TEST_FILE:-tests/sql/10_rules.sql}"; do
  echo "== $f"
  "${P[@]}" -d "$DB" -f "$f" >/dev/null
done
echo "== all SQL loaded and rule tests passed"
