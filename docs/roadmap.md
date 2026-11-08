# Roadmap

Milestones match the GitHub milestones of this repository. A milestone is complete only when all of its acceptance criteria have been verified.

**Release plan:** case 1 is completed through M5 and released first. Cases 2 and 3 follow as updates under the same evidence rules, and each of M2–M5 closes only when all three cases meet it.

| Milestone | Status |
|---|---|
| M0 Repository initialized | Done (2026-11-07) |
| M1 Development environment reproducible | Done (2026-11-08) |
| M2 Core functionality implemented | In progress |
| M3 Automated validation complete | In progress |
| M4 Case studies complete | In progress |
| M5 Portfolio assets complete | In progress (case 1 done) |
| M6 Public release approved | Done for case 1 (2026-11-08); visibility change by the owner |
| M7 Upwork Catalog published | Not started |

## M0 — Repository initialized

- [x] Private repository created, client-facing README, AGENTS.md, roadmap, release checklist
- [x] Public-safety scan passing in CI

Acceptance: the repository clones on its own, documentation is present, and the scan is clean.

## M1 — Development environment reproducible

- [x] Choose and record the reference SQL Server version and edition, plus supported alternatives (see `docs/architecture.md`)
- [x] `sql/00-setup/` creates or resets the lab database idempotently
- [x] A single documented command runs all setup scripts in order with `sqlcmd -b`
- [x] Setup tested from a clean instance and timed

Acceptance: a person with SQL Server and sqlcmd can create an empty lab database by following the README alone.

## M2 — Core functionality implemented

- [x] Schema for customers, categories, products, orders, order items, payments
- [x] Deterministic data generator (seed + scale), tested for identical output across runs
- [ ] Case 1, 2 and 3 baseline scripts that reproduce the slow behavior — case 1 done
- [ ] Optimized scripts for each case — case 1 done

Acceptance: at full scale the baselines are measurably slow, and the optimized versions return identical results.

## M3 — Automated validation complete

- [ ] Result-equivalence tests for all three cases — case 1 done (`tests/case-01-equivalence-test.sh`)
- [x] Benchmark harness producing CSV and Markdown summaries (`benchmarks/run-case.sh`)
- [ ] CI smoke test on a small scale using a free SQL Server service container (needs owner approval before enabling)

Acceptance: tests and harness run from one command, and CI is green.

## M4 — Case studies complete

- [ ] Three case studies with problem, reproduction, baseline metrics, root cause, optimization, after metrics, trade-offs and reproducibility notes — case 1 done
- [ ] Every number traceable to `benchmarks/results/` — case 1 done

## M5 — Portfolio assets complete

- [ ] Sanitized execution-plan and before/after screenshots — case 1 done
- [ ] README results table filled from measured data
- [ ] Upwork portfolio entry and Catalog text finalized (kept in private notes, outside this repository) — case 1 done

## M6 — Public release approved

- [x] Every item in `docs/public-release-checklist.md` verified, including a full history scan
- [x] Owner approval recorded. The visibility change is made by the owner.

## M7 — Upwork Catalog published

- [ ] The owner publishes the portfolio entry and Project Catalog offering
