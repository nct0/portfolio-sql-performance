# AGENTS.md — portfolio-sql-performance

Instructions for AI agents and humans changing this repository. Read this whole file before changing anything.

## Purpose and boundaries

- A reproducible SQL Server performance lab with three measured case studies.
- This repository is self-contained. It must make sense, run and verify when cloned on its own. Do not reference other repositories, private workspaces or local machine paths in any file.
- It may become public later, so treat every commit, including its history, as publishable.

## Privacy and data rules

- Synthetic data only. Generated people use `example.com` / `example.org` emails and obviously fictional names. Payment data holds masked values only: no card numbers, not even test ones.
- Never commit backups or database files (`*.bak`, `*.mdf`, `*.ldf`), connection strings with passwords, or host and instance names from your machine.
- Execution plans and screenshots can leak server, user or machine names. Check them before committing.
- Commit with the repository-local GitHub noreply identity only (`git config user.email` must end in `@users.noreply.github.com`).

## Layout

| Path | Rule |
|---|---|
| `sql/00-setup/` | Create or reset the lab database. Idempotent. |
| `sql/schema/` | Tables, keys, baseline indexes. |
| `sql/data/` | Deterministic data generator with a fixed seed and a configurable scale. |
| `sql/scenarios/case-NN-<slug>/` | `baseline.sql`, `optimized.sql`, `README.md` per case. |
| `benchmarks/` | Harness scripts. `benchmarks/results/` holds sanitized, committed results; `benchmarks/runs/` holds local raw output (git-ignored). |
| `tests/` | Checks that baseline and optimized queries return identical results. |

## SQL conventions

- Scripts run with `sqlcmd -b` (stop on error) and are safe to re-run.
- `SET NOCOUNT ON;` at the top of scripts and procedures; schema-qualified names (`dbo.Orders`); explicit column lists.
- File names: `NN-short-description.sql`, executed in numeric order.
- Optimized queries must return exactly the same rows as their baseline. Prove it with a test.
- Cache-clearing commands (`DBCC DROPCLEANBUFFERS`, `DBCC FREEPROCCACHE`) are only for a dedicated local development instance. Guard and label them clearly.

## Measurement rules (non-negotiable)

- Never invent, round up or estimate numbers. Every published figure comes from a harness run whose sanitized output is committed under `benchmarks/results/`.
- Record the environment: SQL Server version and edition, CPU core count, memory, dataset scale and seed. Never record host or instance names.
- State whether the cache was warm or cold. Run each measurement several times and report the median and range.
- Compare logical reads first (hardware-independent), then CPU and elapsed time.
- If a change does not improve things, document that honestly.

## Testing

- Every scenario needs a result-equivalence check in `tests/`.
- Before every commit, run these checks from the repository root. All must pass:
  ```bash
  bash tests/setup-lab-test.sh                       # setup checks on the default instance
  bash scripts/check-public-safety.sh --history
  ```
  When `sql/00-setup/` changes, also run the setup checks on LocalDB if it is installed: `SQLCMDSERVER='(localdb)\MSSQLLocalDB' bash tests/setup-lab-test.sh`.
- Tests use throwaway databases named `PerfLab_<Purpose>Test` and drop them when they finish. Never point a test at a database you want to keep.
- CI with a SQL Server service container is planned for milestone M3. Do not add workflows that need paid services.

## Documentation

- Case studies follow the sections in `docs/case-studies/README.md`.
- Keep `README.md` client-facing. Update its results table only from committed benchmark results.
- Update `docs/roadmap.md` when a milestone task is finished, and never mark unfinished work as done.

## Commits and release

- Make small conventional commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`), each touching only this repository.
- Run `bash scripts/check-public-safety.sh --history` before pushing.
- Visibility changes need the owner's explicit, recorded approval in `docs/public-release-checklist.md`. Never change visibility, publish packages or deploy anything yourself.
