# Case studies

| # | Case study | File | Status |
|---|---|---|---|
| 1 | Slow filtering and lookup query | [case-01-filtering-lookup.md](case-01-filtering-lookup.md) | Done |
| 2 | Expensive joins and aggregation | `case-02-joins-aggregation.md` | Planned |
| 3 | Inefficient pagination / stored procedure | `case-03-pagination-procedure.md` | Planned |

## Required sections

Each case study contains, in this order:

1. **Problem**: the symptom as a client would describe it.
2. **Reproduction steps**: exact scripts and parameters, starting from a fresh lab database.
3. **Baseline metrics**: logical reads, CPU time and elapsed time (median and range of N runs), with the environment.
4. **Root-cause analysis**: what the execution plan shows, and why.
5. **Optimization**: the change, and why it is the smallest effective one.
6. **After metrics**: the same harness, the same environment and the same data.
7. **Trade-offs**: write cost, storage, maintenance, and plan stability.
8. **Reproducibility notes**: versions, scale, seed, cache state, and known variance.

Metrics are copied from committed files in `benchmarks/results/`, never typed by hand.
