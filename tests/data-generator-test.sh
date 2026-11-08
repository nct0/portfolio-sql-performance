#!/usr/bin/env bash
# data-generator-test.sh - check that the data generator is deterministic and
# produces the documented volumes and synthetic values only.
#
# Usage: data-generator-test.sh
#
# Builds three throwaway lab databases at scale 1: PerfLab_DataATest and
# PerfLab_DataBTest with seed 42, PerfLab_DataCTest with seed 7. All three are
# dropped when the test finishes.
#
# Connection settings: see scripts/setup-lab.sh.
# Exit status: 0 all checks passed, 1 a check failed, 2 environment error.

set -uo pipefail

command -v sqlcmd >/dev/null || { echo "error: sqlcmd not found on PATH" >&2; exit 2; }
cd "$(dirname "$0")/.."

dbs=(PerfLab_DataATest PerfLab_DataBTest PerfLab_DataCTest)
fails=0
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
query() { sqlcmd -b -C -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '\r'; }
drop_dbs() {
  local db
  for db in "${dbs[@]}"; do
    query "IF DB_ID(N'$db') IS NOT NULL BEGIN
             ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db];
           END;" >/dev/null || return 1
  done
}

# Row count and checksum of every generated table, one line per table.
fingerprint() {
  local t out=""
  for t in Categories Products Customers Orders OrderItems Payments; do
    out+="$t $(query "SELECT CONCAT(COUNT_BIG(*), ' ', CHECKSUM_AGG(BINARY_CHECKSUM(*))) FROM [$1].dbo.$t;")"$'\n'
  done
  printf '%s' "$out"
}

drop_dbs || { echo "error: cannot connect with sqlcmd" >&2; exit 2; }
trap drop_dbs EXIT
echo "== data generator tests"

seeds=(42 42 7)
for i in 0 1 2; do
  if out=$(scripts/setup-lab.sh --database "${dbs[$i]}" --scale 1 --seed "${seeds[$i]}" 2>&1); then
    pass "generates ${dbs[$i]} (seed ${seeds[$i]}, scale 1): $(grep -o 'in [0-9]* s\.' <<<"$out" | head -1)"
  else
    printf '%s\n' "$out" | sed 's/^/        /'; echo "error: lab setup failed" >&2; exit 2
  fi
done

a=$(fingerprint "${dbs[0]}"); b=$(fingerprint "${dbs[1]}"); c=$(fingerprint "${dbs[2]}")
if [ "$a" = "$b" ]; then pass "same seed and scale give identical data in every table"
else fail "same seed and scale give different data:"$'\n'"$(diff <(echo "$a") <(echo "$b"))"; fi
if [ "$(grep -v '^Categories' <<<"$a")" != "$(grep -v '^Categories' <<<"$c")" ]; then
  pass "a different seed gives different data"
else fail "seeds 42 and 7 give the same data"; fi

db=${dbs[0]}
counts=$(query "SELECT CONCAT_WS(' ', (SELECT COUNT(*) FROM [$db].dbo.Categories), (SELECT COUNT(*) FROM [$db].dbo.Products),
                                (SELECT COUNT(*) FROM [$db].dbo.Customers), (SELECT COUNT(*) FROM [$db].dbo.Orders));")
if [ "$counts" = "20 5000 10000 100000" ]; then pass "scale 1 volumes: 20 categories, 5,000 products, 10,000 customers, 100,000 orders"
else fail "scale 1 volumes are '$counts'"; fi

lines=$(query "SELECT CONCAT(MIN(n), ' ', MAX(n)) FROM (SELECT COUNT(*) AS n FROM [$db].dbo.OrderItems GROUP BY OrderId) AS t;")
orders_without_lines=$(query "SELECT COUNT(*) FROM [$db].dbo.Orders AS o
                              WHERE NOT EXISTS (SELECT 1 FROM [$db].dbo.OrderItems AS i WHERE i.OrderId = o.OrderId);")
if [ "$lines" = "1 5" ] && [ "$orders_without_lines" = 0 ]; then pass "every order has 1 to 5 lines"
else fail "lines per order: min/max '$lines', orders without lines: $orders_without_lines"; fi

wrong_totals=$(query "SELECT COUNT(*) FROM [$db].dbo.Orders AS o
                      WHERE o.TotalAmount <> (SELECT SUM(i.Quantity * i.UnitPrice) FROM [$db].dbo.OrderItems AS i
                                              WHERE i.OrderId = o.OrderId);")
if [ "$wrong_totals" = 0 ]; then pass "order totals match their lines"; else fail "$wrong_totals order totals differ from their lines"; fi

bad_emails=$(query "SELECT COUNT(*) FROM [$db].dbo.Customers
                    WHERE Email NOT LIKE '%@example.com' AND Email NOT LIKE '%@example.org';")
if [ "$bad_emails" = 0 ]; then pass "every email uses example.com or example.org"
else fail "$bad_emails emails use another domain"; fi

heavy_share=$(query "SELECT COUNT(*) * 100 / (SELECT COUNT(*) FROM [$db].dbo.Orders) FROM [$db].dbo.Orders WHERE CustomerId <= 10;")
if [ "$heavy_share" -ge 5 ] && [ "$heavy_share" -le 6 ]; then pass "customers 1-10 hold ${heavy_share}% of orders (skew)"
else fail "customers 1-10 hold ${heavy_share}% of orders, expected about 5%"; fi

echo "== summary: $fails failure(s)"
[ "$fails" -eq 0 ] || exit 1
