#!/usr/bin/env bash
# setup-lab.sh - build the lab database: run every script in sql/00-setup/,
# sql/schema/ and sql/data/, in that order and in numeric order within each
# folder, with sqlcmd -b, stopping at the first error.
#
# Usage: setup-lab.sh [--database NAME] [--reset] [--scale N] [--seed N] [--no-data]
#
#   --database NAME   Lab database name. Default: PerfLab.
#   --reset           Drop and recreate the database first. All its data is lost.
#   --scale N         Data volume, 1-100: 10,000 customers and 100,000 orders per
#                     unit. Default: 20, the scale of the published measurements.
#   --seed N          Seed of the data generator. Default: 42.
#   --no-data         Create the database and tables, but generate no data.
#
# Re-running with the same seed and scale keeps the existing data. A different
# seed or scale needs --reset.
#
# Connection: sqlcmd's own environment variables. Without them, sqlcmd connects to
# the local default instance with Windows authentication.
#   SQLCMDSERVER                  for example "localhost,1433" or "(localdb)\MSSQLLocalDB"
#   SQLCMDUSER, SQLCMDPASSWORD    SQL authentication, for example for a container
# The connection trusts the server's certificate (-C), which suits a local lab only.
#
# Exit status: 0 ready, 1 a script failed, 2 usage or environment error.

set -euo pipefail

database=PerfLab
reset=0
scale=20
seed=42
stages="sql/00-setup sql/schema sql/data"
while [ $# -gt 0 ]; do
  case "$1" in
    --database)
      [ $# -ge 2 ] || { echo "error: --database needs a name" >&2; exit 2; }
      database=$2; shift 2 ;;
    --reset) reset=1; shift ;;
    --scale|--seed)
      [[ $# -ge 2 && $2 =~ ^-?[0-9]+$ ]] || { echo "error: $1 needs a whole number" >&2; exit 2; }
      if [ "$1" = --scale ]; then scale=$2; else seed=$2; fi
      shift 2 ;;
    --no-data) stages="sql/00-setup sql/schema"; shift ;;
    -h|--help) sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v sqlcmd >/dev/null || { echo "error: sqlcmd not found on PATH" >&2; exit 2; }
cd "$(dirname "$0")/.."

start=$SECONDS
for stage in $stages; do
  for script in "$stage"/[0-9][0-9]-*.sql; do
    echo "== $script"
    sqlcmd -b -C -W -i "$script" -v DatabaseName="$database" Reset="$reset" Seed="$seed" Scale="$scale" || exit 1
  done
done
echo "== lab database $database ready in $((SECONDS - start)) s"
