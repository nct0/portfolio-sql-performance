#!/usr/bin/env bash
# case-01-equivalence-test.sh - prove that the case 1 optimized query returns
# exactly the same rows, in the same order, as the baseline.
#
# Usage: case-01-equivalence-test.sh
#
# Builds a throwaway lab database, PerfLab_EquivalenceTest, at scale 1, and drops
# it when it finishes. For each parameter set below it runs baseline.sql and
# optimized.sql, both without and with the case 1 index, and compares the output
# text exactly.
#
# Connection settings: see scripts/setup-lab.sh.
# Exit status: 0 all checks passed, 1 a check failed, 2 environment error.

set -uo pipefail

command -v sqlcmd >/dev/null || { echo "error: sqlcmd not found on PATH" >&2; exit 2; }
cd "$(dirname "$0")/.."

db=PerfLab_EquivalenceTest
case_dir=sql/scenarios/case-01-filtering-lookup
fails=0
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
query() { sqlcmd -b -C -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '\r'; }
drop_db() {
  query "IF DB_ID(N'$db') IS NOT NULL BEGIN
           ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db];
         END;" >/dev/null
}
tmp=$(mktemp -d)
cleanup() { drop_db; rm -rf "$tmp"; }

drop_db || { echo "error: cannot connect with sqlcmd" >&2; exit 2; }
trap cleanup EXIT
echo "== case 1 equivalence tests on database $db"
scripts/setup-lab.sh --database "$db" --scale 1 > "$tmp/setup.txt" 2>&1 \
  || { sed 's/^/        /' "$tmp/setup.txt"; echo "error: lab setup failed" >&2; exit 2; }

email() { query "SELECT Email FROM [$db].dbo.Customers WHERE CustomerId = $1;"; }
typical=$(email 1234)
heavy=$(email 3)
# Exact timestamps of customer 3's 50th and 150th orders: the range starts on an
# order and ends on another, so a shifted or inclusive boundary changes the rows.
order_at() {
  query "SELECT CONVERT(varchar(19), OrderDate, 126) FROM (SELECT OrderDate, ROW_NUMBER() OVER (ORDER BY OrderDate, OrderId) AS rn
         FROM [$db].dbo.Orders WHERE CustomerId = 3) AS t WHERE rn = $1;"
}
boundary_from=$(order_at 50)
boundary_to=$(order_at 150)
# label|email|from|to|minimum rows the baseline must return
param_sets=(
  "range boundaries on exact order timestamps|$heavy|$boundary_from|$boundary_to|100"
  "typical customer, one year|$typical|2025-01-01|2026-01-01|1"
  "high-volume customer, one year|$heavy|2025-01-01|2026-01-01|100"
  "high-volume customer, all three years|$heavy|2023-01-01|2026-01-01|400"
  "email in upper case|${typical^^}|2023-01-01|2026-01-01|1"
  "unknown email|nobody@example.com|2023-01-01|2026-01-01|0"
)

# run SCRIPT EMAIL FROM TO OUT: query output without the database-context message.
# The dates go in as environment variables, which sqlcmd also reads as scripting
# variables: -v rejects values that contain ':', such as a time of day.
run() {
  FromDate=$3 ToDate=$4 sqlcmd -b -C -h -1 -W -s '|' -i "$case_dir/$1" \
    -v DatabaseName="$db" Email="$2" 2>&1 \
    | tr -d '\r' | sed '/^Changed database context/d' > "$5"
}

for index in index-drop.sql index-create.sql; do
  sqlcmd -b -C -i "$case_dir/$index" -v DatabaseName="$db" >/dev/null || { fail "$index failed"; continue; }
  for set in "${param_sets[@]}"; do
    IFS='|' read -r label email from to min_rows <<<"$set"
    if ! run baseline.sql "$email" "$from" "$to" "$tmp/baseline.txt" \
       || ! run optimized.sql "$email" "$from" "$to" "$tmp/optimized.txt"; then
      fail "$label ($index): a query failed"; continue
    fi
    rows=$(grep -c . "$tmp/baseline.txt")
    if [ "$rows" -lt "$min_rows" ]; then fail "$label ($index): only $rows rows, expected at least $min_rows"
    elif diff -q "$tmp/baseline.txt" "$tmp/optimized.txt" >/dev/null; then pass "$label ($index): $rows identical rows"
    else fail "$label ($index): results differ"; fi
  done
done

echo "== summary: $fails failure(s)"
[ "$fails" -eq 0 ] || exit 1
