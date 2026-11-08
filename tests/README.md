# Tests

| Test | Checks | Run |
|---|---|---|
| `setup-lab-test.sh` | Lab setup: settings of a new database, idempotent re-runs, `--reset` (also with an open session), rejection of invalid input, the collation guard, and that a failed create is reported as an error | `bash tests/setup-lab-test.sh` |
| `data-generator-test.sh` | Data generator: identical data for the same seed and scale, different data for another seed, volumes, order totals, example-domain emails and skew. Uses `PerfLab_DataATest`, `PerfLab_DataBTest` and `PerfLab_DataCTest` (about 1 minute) | `bash tests/data-generator-test.sh` |
| `case-01-equivalence-test.sh` | Case 1: baseline and optimized queries return identical rows in the same order, without and with the case index, for six parameter sets, including a range that starts and ends on exact order timestamps. Uses `PerfLab_EquivalenceTest` at scale 1. On 2026-11-08 it was also run against seven deliberately broken optimized queries and caught six; a removed `OrderId` tie-breaker cannot be caught because the test customers have no orders with equal timestamps | `bash tests/case-01-equivalence-test.sh` |

Each test uses throwaway databases named `PerfLab_<Purpose>Test` and drops them when it finishes. The setup test uses `PerfLab_SetupTest` and `PerfLab_BlockerTest`, and runs setup with `--no-data`. Connection settings are the same as for `scripts/setup-lab.sh`.

Planned for milestone M3: result-equivalence checks for cases 2 and 3.
