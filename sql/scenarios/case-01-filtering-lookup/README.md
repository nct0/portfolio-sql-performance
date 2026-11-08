# Case 1: slow filtering and lookup query

A customer-service screen lists a customer's orders for a date range, looked up by email. Full write-up: [docs/case-studies/case-01-filtering-lookup.md](../../../docs/case-studies/case-01-filtering-lookup.md).

| File | Purpose |
|---|---|
| `baseline.sql` | The query as the application sends it: the email parameter is `nvarchar`, as .NET sends strings by default |
| `optimized.sql` | The same query with the email parameter declared as `varchar(254)`, the column's type |
| `index-create.sql` | Adds `IX_Orders_CustomerId_OrderDate` (key `CustomerId, OrderDate`, includes `Status, TotalAmount`) |
| `index-drop.sql` | Removes that index again |
| `benchmark.conf` | Parameters and the four measured variants: a typical customer, 2025 |
| `benchmark-high-volume.conf` | The same variants for high-volume customer 3, 2025 |
| `benchmark-wide-range.conf` | The same variants for customer 3 over 2023-2025 |

All scripts take the sqlcmd variable `DatabaseName`; the query scripts also take `Email`, `FromDate` and `ToDate`.

```bash
# Measure all four variants (writes benchmarks/results/case-01-filtering-lookup.*)
bash benchmarks/run-case.sh sql/scenarios/case-01-filtering-lookup

# Save the actual execution plans to open in SSMS
bash benchmarks/capture-plans.sh sql/scenarios/case-01-filtering-lookup

# Prove the optimized query returns exactly the same rows
bash tests/case-01-equivalence-test.sh
```

Add `--conf benchmark-high-volume.conf` or `--conf benchmark-wide-range.conf` to `run-case.sh` or `capture-plans.sh` for the other parameter sets. The parameters in `benchmark.conf` name customer 150000, which exists only at scale 20 (the default). At a smaller scale, pick a customer below 10,000 × scale, or the query measures a lookup that finds nobody.

The benchmark leaves the case 1 index in place (its last variant creates it). Run `index-drop.sql` to return to the baseline schema.
