# SQL scripts

Layout (milestones M1–M2). Scripts run in numeric order with `sqlcmd -b`:

| Folder | Contents | Status |
|---|---|---|
| `00-setup/` | Create or reset the lab database (idempotent) | Implemented |
| `schema/` | Tables, keys and baseline indexes | Implemented |
| `data/` | Deterministic synthetic data generator (seed + scale) | Implemented |
| `scenarios/case-NN-<slug>/` | `baseline.sql`, `optimized.sql` and notes for each case study | Case 1 implemented |

## Setup scripts

Run every script in `00-setup/`, `schema/` and `data/`, in that order, with one command:

```bash
scripts/setup-lab.sh                     # create PerfLab at scale 20, or keep it if it exists
scripts/setup-lab.sh --reset             # drop and recreate it; all data is lost
scripts/setup-lab.sh --database MyLab    # another database name
scripts/setup-lab.sh --scale 1           # a small dataset for quick functional runs
scripts/setup-lab.sh --no-data           # database and tables only
```

Connection settings come from sqlcmd's environment variables (`SQLCMDSERVER`, `SQLCMDUSER`, `SQLCMDPASSWORD`). Without them, the script uses the local default instance with Windows authentication. See `scripts/setup-lab.sh --help`.

`00-setup/01-create-database.sql` creates the lab database with a pinned collation (`SQL_Latin1_General_CP1_CI_AS`), SIMPLE recovery, AUTO_CLOSE off and Query Store on. Run on its own, it needs two sqlcmd variables:

| Variable | Values |
|---|---|
| `DatabaseName` | Letters, digits and underscores only, for example `PerfLab` |
| `Reset` | `0` keeps an existing database; `1` drops and recreates it, deleting all data |

```bash
sqlcmd -C -b -i sql/00-setup/01-create-database.sql -v DatabaseName=PerfLab Reset=0
```

The script stops with an error if the name is invalid, if it names a system database, or if an existing database has a different collation. `tests/setup-lab-test.sh` checks each of these cases.

## Schema

`schema/01-tables.sql` creates six order-management tables plus `dbo.LabInfo`, which records the seed and scale of the generated data:

| Table | Key | Notes |
|---|---|---|
| `dbo.Categories` | `CategoryId` | 20 fixed categories |
| `dbo.Products` | `ProductId` | 5,000 products |
| `dbo.Customers` | `CustomerId` | `Email` is `varchar(254)` with a unique constraint |
| `dbo.Orders` | `OrderId` | Foreign key to `Customers`, deliberately without a supporting index |
| `dbo.OrderItems` | `OrderId, LineNumber` | 1-5 lines per order |
| `dbo.Payments` | `PaymentId` | Payment attempts; no card data of any kind |

Only primary keys, foreign keys and the email constraint exist at first. Each case study adds the indexes it needs, so that their effect can be measured in isolation.

## Data generator

`data/01-generate.sql` fills the tables with set-based T-SQL. Every pseudo-random value is a slice of `HASHBYTES('SHA2_256', seed | table | row number)`, so the same seed and scale always produce exactly the same rows. `tests/data-generator-test.sh` checks this.

| Scale | Customers | Orders | Order items | Payments | Build time* |
|---|---|---|---|---|---|
| 1 | 10,000 | 100,000 | 299,390 | 94,791 | 24 s |
| 20 (default) | 200,000 | 2,000,000 | 5,998,787 | 1,895,123 | 427 s |

\* Seed 42, measured once on the reference machine (SQL Server 2022 Developer, 20 logical CPUs). Expect different times elsewhere.

The data has deliberate skew, so that plans depend on parameter values: 5% of all orders belong to customers 1-10, 20% fall in November and December, and 30% of order lines use the 100 most popular products. Names are fictional and every email uses `example.com` or `example.org`.

After loading, the generator creates single-column statistics on every column and rebuilds all statistics with `FULLSCAN`, so query estimates do not depend on sampling.

Re-running with the same seed and scale keeps the data. Other existing data stops the script with Msg 50102; rebuild with `--reset`.
