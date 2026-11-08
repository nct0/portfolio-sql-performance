# Benchmarks

| Script | Purpose |
|---|---|
| `run-case.sh CASE_DIR` | Measures every variant listed in `CASE_DIR/benchmark.conf`: one warm-up run, then 11 measured runs under `SET STATISTICS IO, TIME ON` (logical reads, CPU and elapsed time in whole milliseconds), the rows returned, and 3 timed loops: the query back to back for 2 seconds, giving the mean elapsed time per execution in microseconds, including returning rows to the client |
| `capture-plans.sh CASE_DIR` | Saves the actual execution plan of every variant as a `.sqlplan` file, to open in SQL Server Management Studio |

Both take `--database NAME` (default `PerfLab`) and `--conf benchmark-<name>.conf` for another parameter set of the same case; results are then named `<case>-<name>`. Connection settings are the same as for `scripts/setup-lab.sh`.

- `runs/`: raw local output and plans, git-ignored because they may contain server or instance names.
- `results/`: sanitized CSV (every run, every timed loop) and Markdown (environment, medians and ranges), committed. They are the only source for published numbers.

| Case | Results |
|---|---|
| 1. Slow filtering and lookup query | [typical customer](results/case-01-filtering-lookup.md), [high-volume customer](results/case-01-filtering-lookup-high-volume.md), [high-volume customer, 3 years](results/case-01-filtering-lookup-wide-range.md) |
