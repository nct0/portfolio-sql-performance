#!/usr/bin/env bash
# setup-lab-test.sh - check that the lab setup is idempotent and rejects bad input.
#
# Usage: setup-lab-test.sh
#
# Runs scripts/setup-lab.sh against throwaway databases, PerfLab_SetupTest and
# PerfLab_BlockerTest, on the server that sqlcmd connects to (connection settings:
# see scripts/setup-lab.sh). Both are dropped before and after the checks, so never
# use those names for anything else. Setup runs with --no-data; the generator has
# its own test, tests/data-generator-test.sh.
#
# Exit status: 0 all checks passed, 1 a check failed, 2 environment error.

set -uo pipefail

command -v sqlcmd >/dev/null || { echo "error: sqlcmd not found on PATH" >&2; exit 2; }
cd "$(dirname "$0")/.."

db=PerfLab_SetupTest
blocker=PerfLab_BlockerTest
expected_settings="SQL_Latin1_General_CP1_CI_AS SIMPLE autoclose=0 querystore=1"
fails=0
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }

# One value from a query, without the carriage returns sqlcmd prints on Windows.
query() { sqlcmd -b -C -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '\r'; }
drop_db() {
  local name
  for name in "$db" "$blocker"; do
    query "IF DB_ID(N'$name') IS NOT NULL BEGIN
             ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name];
           END;" >/dev/null || return 1
  done
}
created() { query "SELECT CONVERT(varchar(30), create_date, 126) FROM sys.databases WHERE name = N'$db';"; }
settings() {
  query "SELECT CONCAT_WS(' ', collation_name COLLATE DATABASE_DEFAULT, recovery_model_desc,
                          CONCAT('autoclose=', is_auto_close_on), CONCAT('querystore=', is_query_store_on))
         FROM sys.databases WHERE name = N'$db';"
}

# Runs the setup on the test database; prints its output only when it fails.
setup() {
  local out
  out=$(scripts/setup-lab.sh --database "$db" --no-data "$@" 2>&1) || { printf '%s\n' "$out" | sed 's/^/        /'; return 1; }
}

# expect_failure LABEL TEXT COMMAND...: the command must fail and print TEXT.
expect_failure() {
  local label=$1 text=$2 out; shift 2
  if out=$("$@" 2>&1); then fail "$label: succeeded"
  elif grep -qF -- "$text" <<<"$out"; then pass "$label"
  else fail "$label: failed without \"$text\""; fi
}

drop_db || { echo "error: cannot connect with sqlcmd" >&2; exit 2; }
trap drop_db EXIT
echo "== setup-lab tests on database $db"

if setup && [ "$(settings)" = "$expected_settings" ]; then
  pass "fresh create applies collation, SIMPLE recovery, AUTO_CLOSE off and Query Store"
else
  fail "fresh create: settings are '$(settings)'"
fi

tables=$(query "SELECT STRING_AGG(name, ' ') WITHIN GROUP (ORDER BY name) FROM [$db].sys.tables;")
if [ "$tables" = "Categories Customers LabInfo OrderItems Orders Payments Products" ]; then
  pass "creates the lab tables"
else
  fail "tables are '$tables'"
fi

first=$(created)
if setup && [ "$(created)" = "$first" ]; then pass "re-run keeps the existing database"
else fail "re-run failed or recreated the database"; fi

if setup --reset && second=$(created) && [ -n "$second" ] && [ "$second" != "$first" ]; then
  pass "--reset recreates the database"
else
  fail "--reset failed or kept the old database"; second=$(created)
fi

sqlcmd -C -d "$db" -Q "WAITFOR DELAY '00:00:20';" >/dev/null 2>&1 &
holder=$!
sessions=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sessions=$(query "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE database_id = DB_ID(N'$db');") || sessions=0
  [ "$sessions" -gt 0 ] && break
  sleep 0.5
done
if [ "$sessions" -eq 0 ]; then fail "--reset with an open session: could not open the session"
elif setup --reset && [ "$(created)" != "$second" ]; then pass "--reset disconnects open sessions"
else fail "--reset with an open session failed"; fi
wait "$holder" 2>/dev/null

expect_failure "rejects an invalid database name" "Msg 50001," scripts/setup-lab.sh --database 'Bad]Name'
expect_failure "rejects a system database" "Msg 50002," scripts/setup-lab.sh --database master
expect_failure "rejects Reset other than 0 or 1" "Msg 50003," \
  sqlcmd -b -C -i sql/00-setup/01-create-database.sql -v DatabaseName="$db" Reset=2
expect_failure "requires the sqlcmd variables" "scripting variable not defined" \
  sqlcmd -b -C -i sql/00-setup/01-create-database.sql

drop_db
query "CREATE DATABASE [$db] COLLATE Latin1_General_CI_AS;" >/dev/null
expect_failure "stops on an existing database with another collation" "Msg 50004," \
  scripts/setup-lab.sh --database "$db"
if setup --reset && [ "$(settings)" = "$expected_settings" ]; then pass "--reset replaces the wrong collation"
else fail "--reset did not replace the wrong collation"; fi

# A blocker database owns the data file name that CREATE DATABASE would use,
# so the create fails the same way as with files left behind by another instance.
drop_db
query "DECLARE @path nvarchar(4000) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(4000));
       DECLARE @sql nvarchar(max) = N'CREATE DATABASE [$blocker]
           ON (NAME = blocker, FILENAME = N''' + @path + N'$db.mdf'')
           LOG ON (NAME = blocker_log, FILENAME = N''' + @path + N'${blocker}_log.ldf'');';
       EXEC (@sql);" >/dev/null
if out=$(scripts/setup-lab.sh --database "$db" 2>&1); then fail "failed create: setup succeeded"
elif ! grep -qF "Msg 5170," <<<"$out"; then fail "failed create: no Msg 5170 (file already exists)"
elif grep -qF "Created database" <<<"$out"; then fail "failed create: still reports 'Created database'"
else pass "a failed create is reported as an error, not as created"; fi

echo "== summary: $fails failure(s)"
[ "$fails" -eq 0 ] || exit 1
