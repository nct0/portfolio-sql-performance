#!/usr/bin/env bash
# run-case.sh - measure every variant of one case study and write sanitized results.
#
# Usage: benchmarks/run-case.sh CASE_DIR [--conf FILE] [--database NAME] [--runs N]
#
#   CASE_DIR          for example sql/scenarios/case-01-filtering-lookup
#   --conf FILE       Benchmark definition inside CASE_DIR. Default: benchmark.conf.
#                     benchmark-<name>.conf writes results named <case>-<name>.
#   --database NAME   Lab database, built with scripts/setup-lab.sh. Default: PerfLab.
#   --runs N          Measured runs per variant, after one warm-up run. Default: 11.
#
# The benchmark definition lists the query parameters and the variants:
#   param NAME VALUE                  a sqlcmd variable passed to every script
#   variant NAME SETUP_SQL QUERY_SQL  SETUP_SQL runs once, then QUERY_SQL is measured
#
# Each run executes QUERY_SQL under SET STATISTICS IO, TIME ON with a warm cache.
# Logical reads are summed over all tables. CPU and elapsed time come from the
# last "SQL Server Execution Times" block, which covers the whole statement;
# SQL Server reports both in whole milliseconds.
#
# For a finer elapsed time, each variant then runs 3 timed loops: QUERY_SQL
# back to back in one batch for 2 seconds, timed with SYSDATETIME() over the
# whole loop. The mean per execution is the loop time divided by the number of
# executions. It includes returning the rows to the client.
#
# Output:
#   benchmarks/runs/<case>-<timestamp>/        raw sqlcmd output (git-ignored; may
#                                              contain server names)
#   benchmarks/results/<case>.csv              every measured run
#   benchmarks/results/<case>-loop.csv         every timed loop
#   benchmarks/results/<case>.md               environment, medians and ranges
# Only parsed numbers reach benchmarks/results/. No host or instance names.
#
# Connection: as scripts/setup-lab.sh (SQLCMDSERVER, SQLCMDUSER, SQLCMDPASSWORD).
# Exit status: 0 done, 1 a script failed, 2 usage or environment error.

set -euo pipefail

usage() { sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; }
case_dir=${1:-}
[ -n "$case_dir" ] && [ "$case_dir" != -h ] && [ "$case_dir" != --help ] || { usage; exit 2; }
shift
database=PerfLab
runs=11
conf_file=benchmark.conf
while [ $# -gt 0 ]; do
  case "$1" in
    --database) [ $# -ge 2 ] || { echo "error: --database needs a name" >&2; exit 2; }; database=$2; shift 2 ;;
    --conf) [[ $# -ge 2 && $2 =~ ^benchmark(-[a-z0-9-]+)?\.conf$ ]] || { echo "error: --conf needs benchmark.conf or benchmark-<name>.conf" >&2; exit 2; }; conf_file=$2; shift 2 ;;
    --runs) [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || { echo "error: --runs needs a positive number" >&2; exit 2; }; runs=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v sqlcmd >/dev/null || { echo "error: sqlcmd not found on PATH" >&2; exit 2; }
cd "$(dirname "$0")/.."
case_dir=${case_dir%/}
conf=$case_dir/$conf_file
[ -f "$conf" ] || { echo "error: $conf not found" >&2; exit 2; }
suffix=${conf_file#benchmark}
case_name=$(basename "$case_dir")${suffix%.conf}

vars=(DatabaseName="$database")
variants=()
while read -r kind a b c; do
  case "$kind" in
    param) vars+=("$a=$b") ;;
    variant) variants+=("$a $b $c") ;;
    ''|'#'*) ;;
    *) echo "error: $conf: unknown line '$kind'" >&2; exit 2 ;;
  esac
done < <(tr -d '\r' < "$conf")

raw=benchmarks/runs/$case_name-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$raw" benchmarks/results
csv=benchmarks/results/$case_name.csv
loop_csv=benchmarks/results/$case_name-loop.csv
md=benchmarks/results/$case_name.md

value() { sqlcmd -b -C -h -1 -W -d "$database" -Q "SET NOCOUNT ON; $1" | tr -d '\r'; }
lab=$(value "SELECT CONCAT(Seed, ' ', Scale) FROM dbo.LabInfo;") || exit 1
[ -n "$lab" ] || { echo "error: $database has no generated data; run scripts/setup-lab.sh" >&2; exit 2; }
read -r seed scale <<<"$lab"
env_line=$(value "SELECT CONCAT_WS('|', CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)),
                    CAST(SERVERPROPERTY('Edition') AS nvarchar(128)),
                    (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()),
                    (SELECT cpu_count FROM sys.dm_os_sys_info),
                    (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info),
                    CAST((SELECT value_in_use FROM sys.configurations WHERE name = 'max degree of parallelism') AS int),
                    CAST((SELECT value_in_use FROM sys.configurations WHERE name = 'cost threshold for parallelism') AS int));") || exit 1
IFS='|' read -r version edition compat cpus memory_mb maxdop ctfp <<<"$env_line"

# measure QUERY_SQL OUT_FILE: one run; prints "reads cpu_ms elapsed_ms".
measure() {
  local wrapper=$raw/wrapper.sql
  printf 'SET STATISTICS IO, TIME ON;\nGO\n:r %s\n' "$1" > "$wrapper"
  sqlcmd -b -C -W -i "$wrapper" -v "${vars[@]}" > "$2" 2>&1 || { cat "$2" >&2; return 1; }
  local reads times
  reads=$(grep -o 'logical reads [0-9]*' "$2" | awk '{s += $3} END {print s + 0}')
  times=$(tr -d '\r' < "$2" | grep -o 'CPU time = [0-9]* ms, *elapsed time = [0-9]* ms' | tail -1 \
          | awk '{print $4, $9}')
  [ -n "$times" ] || { echo "error: no execution times in $2" >&2; return 1; }
  echo "$reads $times"
}

# rows QUERY_SQL: number of rows the query returns.
rows() {
  sqlcmd -b -C -h -1 -W -s '|' -i "$1" -v "${vars[@]}" | tr -d '\r' \
    | sed '/^Changed database context/d' | grep -c . || true
}

# timed_loop QUERY_SQL: prints "executions total_us".
timed_loop() {
  local wrapper=$raw/loop.sql
  printf '%s\n' 'SET NOCOUNT ON;' 'DECLARE @i int = 0, @t0 datetime2(7) = SYSDATETIME();' \
    'WHILE DATEDIFF_BIG(millisecond, @t0, SYSDATETIME()) < 2000' 'BEGIN' ":r $1" 'SET @i += 1;' 'END;' \
    "PRINT CONCAT('loop ', @i, ' ', DATEDIFF_BIG(microsecond, @t0, SYSDATETIME()));" > "$wrapper"
  sqlcmd -b -C -W -i "$wrapper" -v "${vars[@]}" | tr -d '\r' | sed -n 's/^loop \([0-9]*\) \([0-9]*\)$/\1 \2/p'
}

echo "variant,run,logical_reads,cpu_ms,elapsed_ms" > "$csv"
echo "variant,loop,executions,total_us,mean_us" > "$loop_csv"
declare -A row_count
for v in "${variants[@]}"; do
  read -r name setup query <<<"$v"
  echo "== $name: $setup, then $query x $runs"
  sqlcmd -b -C -W -i "$case_dir/$setup" -v "${vars[@]}" > "$raw/$name-setup.txt" 2>&1 \
    || { cat "$raw/$name-setup.txt" >&2; exit 1; }
  measure "$case_dir/$query" "$raw/$name-warmup.txt" >/dev/null || exit 1
  for ((i = 1; i <= runs; i++)); do
    m=$(measure "$case_dir/$query" "$raw/$name-run$i.txt") || exit 1
    echo "$name,$i,${m// /,}" >> "$csv"
  done
  row_count[$name]=$(rows "$case_dir/$query") || exit 1
  for ((i = 1; i <= 3; i++)); do
    read -r n us <<<"$(timed_loop "$case_dir/$query")"
    [ -n "${n:-}" ] && [ "$n" -gt 0 ] || { echo "error: timed loop of $name failed" >&2; exit 1; }
    echo "$name,$i,$n,$us,$((us / n))" >> "$loop_csv"
  done
done

# Median (middle value; the mean of the two middle values for an even count) and range.
stats() {
  sort -n | awk '{a[NR] = $1} END {
    m = (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2
    if (a[1] == a[NR]) printf "%s", m; else printf "%s (%s–%s)", m, a[1], a[NR] }'
}
{
  echo "# Benchmark results: $case_name"
  echo
  echo "Generated by \`benchmarks/run-case.sh\` on $(date -u +%Y-%m-%d). Do not edit by hand."
  echo
  echo "| Setting | Value |"
  echo "|---|---|"
  echo "| SQL Server | $version, $edition |"
  echo "| Compatibility level | $compat |"
  echo "| Logical CPUs / memory | $cpus / $memory_mb MB |"
  echo "| MAXDOP / cost threshold for parallelism | $maxdop / $ctfp |"
  echo "| Data | seed $seed, scale $scale |"
  echo "| Parameters | $(printf '%s ' "${vars[@]:1}")|"
  echo "| Cache | warm: one discarded warm-up run, then $runs measured runs and 3 timed loops per variant |"
  echo
  echo "Median, with the range in brackets when the runs differ. Logical reads, CPU ms and elapsed ms come from"
  echo "SET STATISTICS IO, TIME, which reports whole milliseconds. The last column is the mean elapsed time per"
  echo "execution in 2-second timed loops, including returning rows to the client (median of 3 loops)."
  echo
  echo "| Variant | Rows | Logical reads | CPU ms | Elapsed ms | Loop mean µs |"
  echo "|---|---|---|---|---|---|"
  for v in "${variants[@]}"; do
    read -r name _ _ <<<"$v"
    runs_of=$(grep "^$name," "$csv")
    loops_of=$(grep "^$name," "$loop_csv")
    echo "| $name | ${row_count[$name]} | $(cut -d, -f3 <<<"$runs_of" | stats) | $(cut -d, -f4 <<<"$runs_of" | stats)" \
         "| $(cut -d, -f5 <<<"$runs_of" | stats) | $(cut -d, -f5 <<<"$loops_of" | stats) |"
  done
} > "$md"
echo "== results: $csv, $loop_csv, $md (raw output: $raw)"
