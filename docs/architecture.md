# Architecture

> Status: the environment, schema, data generator, benchmark harness and case 1 are implemented. Cases 2 and 3 are planned.

## Overview

```text
sql/00-setup ──► sql/schema ──► sql/data (deterministic generator)
                                     │
                     ┌───────────────┴───────────────┐
              scenarios/case-NN/baseline.sql   scenarios/case-NN/optimized.sql
                     └───────────────┬───────────────┘
                     tests/ (result equivalence)   benchmarks/ (harness → results/)
                                     │
                          docs/case-studies/case-NN.md
```

## Data model

| Table | Purpose | Notes |
|---|---|---|
| `dbo.Customers` | Synthetic customers | Email addresses on reserved example domains only |
| `dbo.Products` | Catalog with categories | |
| `dbo.Categories` | Product categories | |
| `dbo.Orders` | Order header: customer, status, dates, totals | Main fact table for filtering and pagination |
| `dbo.OrderItems` | Order lines | Largest table; drives join and aggregation cost |
| `dbo.Payments` | Payment attempts per order | Masked values only |

The schema deliberately starts with only primary keys and the obvious foreign keys. Each case study adds the indexes it needs, so that their effect can be measured in isolation.

## Data generation

- Set-based T-SQL using a numbers source and hash-based pseudo-random values. The same seed and scale always produce identical data.
- A `@Scale` parameter sets volume. The target is large enough for plan differences to be measurable: roughly millions of order items at full scale, with a small scale for quick runs and CI.
- Realistic skew, such as a few very active customers and seasonal order dates, so that parameter sensitivity can be shown.

## Case study design

| Case | Planned problem | Planned techniques |
|---|---|---|
| 1. Filtering and lookup | Non-sargable predicates, implicit conversion, missing composite index | Predicate rewrite, composite covering index, key-order reasoning |
| 2. Joins and aggregation | Revenue report with redundant joins and row-by-row logic, key lookups | Rewrite, pre-aggregation, covering indexes; columnstore evaluated only if justified |
| 3. Pagination / stored procedure | `OFFSET` deep paging; catch-all procedure with parameter-sensitive plans | Keyset pagination; `OPTION (RECOMPILE)` or parameterized dynamic SQL, with trade-offs |

## Measurement harness

- Runs each query N times under `SET STATISTICS IO, TIME ON` and captures logical reads, CPU time and elapsed time.
- Uses Query Store as a second source where available.
- Writes raw output to `benchmarks/runs/` (ignored) and a sanitized summary (CSV + Markdown) to `benchmarks/results/`.
- Records the environment without identifying hostnames.

## Environment (decided in M1)

| Role | Engine | Use |
|---|---|---|
| Reference | SQL Server 2022 Developer Edition, CU27 (16.0.4305.5) | All published measurements |
| Supported | SQL Server 2019 or later, any edition, including Express and LocalDB | Setup, tests and functional runs. Timings and plans may differ |

- Developer Edition is free for development and includes every Enterprise feature. When a result depends on an Enterprise-only feature, the case study says so, because many client servers run Standard Edition.
- Measurements use the default database compatibility level of the reference engine (160). Plans can differ at other levels, such as 150 on SQL Server 2019 and 170 on SQL Server 2025.
- Each benchmark result records the exact version, edition and compatibility level it was measured on.
- A container image remains an option for people who have Docker.
- No cloud resources and no paid services.
