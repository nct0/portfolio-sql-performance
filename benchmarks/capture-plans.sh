#!/usr/bin/env bash
# capture-plans.sh - save the actual execution plan of every variant of one case.
#
# Usage: benchmarks/capture-plans.sh CASE_DIR [--conf FILE] [--database NAME]
#
# Reads CASE_DIR/benchmark.conf (or --conf FILE) like run-case.sh, runs each variant once with
# SET STATISTICS XML ON, and writes one .sqlplan file per variant to
# benchmarks/runs/<case>-plans-<timestamp>/. Open them in SQL Server Management
# Studio for the graphical plan. The files stay in the git-ignored runs folder:
# review them for server, user and machine names before copying one anywhere else.
#
# Connection: as scripts/setup-lab.sh. Exit status: 0 done, 1 failed, 2 usage error.

set -euo pipefail

case_dir=${1:-}
[ -n "$case_dir" ] && [ "${case_dir:0:1}" != - ] || { sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; exit 2; }
shift
database=PerfLab
conf_file=benchmark.conf
while [ $# -gt 0 ]; do
  case "$1" in
    --conf) [[ $# -ge 2 && $2 =~ ^benchmark(-[a-z0-9-]+)?\.conf$ ]] || { echo "error: --conf needs benchmark.conf or benchmark-<name>.conf" >&2; exit 2; }; conf_file=$2; shift 2 ;;
    --database) [ $# -ge 2 ] || { echo "error: --database needs a name" >&2; exit 2; }; database=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v sqlcmd >/dev/null || { echo "error: sqlcmd not found on PATH" >&2; exit 2; }
cd "$(dirname "$0")/.."
case_dir=${case_dir%/}
conf=$case_dir/$conf_file
suffix=${conf_file#benchmark}
[ -f "$conf" ] || { echo "error: $conf not found" >&2; exit 2; }

vars=(DatabaseName="$database")
variants=()
while read -r kind a b c; do
  case "$kind" in
    param) vars+=("$a=$b") ;;
    variant) variants+=("$a $b $c") ;;
  esac
done < <(tr -d '\r' < "$conf")

out_dir=benchmarks/runs/$(basename "$case_dir")${suffix%.conf}-plans-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$out_dir"
for v in "${variants[@]}"; do
  read -r name setup query <<<"$v"
  sqlcmd -b -C -i "$case_dir/$setup" -v "${vars[@]}" >/dev/null
  printf 'SET STATISTICS XML ON;\nGO\n:r %s\n' "$case_dir/$query" > "$out_dir/wrapper.sql"
  # -y 0 prints the plan XML without truncation; keep only the plan document.
  sqlcmd -b -C -y 0 -i "$out_dir/wrapper.sql" -v "${vars[@]}" | tr -d '\r' \
    | sed -n 's/.*\(<ShowPlanXML.*<\/ShowPlanXML>\).*/\1/p' > "$out_dir/$name.sqlplan"
  [ -s "$out_dir/$name.sqlplan" ] || { echo "error: no plan captured for $name" >&2; exit 1; }
  echo "== $out_dir/$name.sqlplan"
done
rm -f "$out_dir/wrapper.sql"
