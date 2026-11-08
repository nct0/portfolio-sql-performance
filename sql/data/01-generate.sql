/*
    Fills the lab tables with synthetic order-management data.

    Deterministic: every pseudo-random value is a slice of
    HASHBYTES('SHA2_256', seed | table | row number), so the same Seed and Scale
    always produce exactly the same rows, on any machine.

    Volumes per Scale unit: 10,000 customers and 100,000 orders with 1-5 lines
    each (about 300,000 order items) and about one payment attempt per order.
    Categories (20) and products (5,000) do not grow with Scale.
    Published measurements use Scale 20: 200,000 customers and 2,000,000 orders.

    Skew, so that plans depend on parameter values:
      - 5% of all orders belong to customers 1-10 (high-volume accounts)
      - 20% of orders fall in November and December (seasonal peak)
      - 30% of order lines use the 100 most popular products

    Safe to re-run: when the database already holds data with the same Seed and
    Scale it is kept. Other existing data stops the script; recreate the lab with
    Reset=1 (scripts/setup-lab.sh --reset) first.

    sqlcmd variables:
      DatabaseName  lab database
      Seed          any int, for example 42
      Scale         1-100
*/
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
USE [$(DatabaseName)];
GO

DECLARE @Seed int = $(Seed), @Scale int = $(Scale);
IF @Scale NOT BETWEEN 1 AND 100
    THROW 50101, N'Scale must be between 1 and 100.', 1;

IF EXISTS (SELECT 1 FROM dbo.LabInfo WHERE Seed = @Seed AND Scale = @Scale)
BEGIN
    PRINT CONCAT(N'Data for seed ', @Seed, N' and scale ', @Scale, N' already generated; kept.');
    RETURN;
END;
IF EXISTS (SELECT 1 FROM dbo.LabInfo) OR EXISTS (SELECT 1 FROM dbo.Categories)
    THROW 50102, N'The database holds other or partial data. Recreate it with Reset=1 first.', 1;

DECLARE @Customers int = 10000 * @Scale,
        @Orders    int = 100000 * @Scale,
        @Products  int = 5000,
        @Start     datetime2(7) = SYSDATETIME();

-- Row numbers 1..@Orders, the largest row count needed.
DROP TABLE IF EXISTS #Numbers;
CREATE TABLE #Numbers (n int NOT NULL PRIMARY KEY);
WITH E1(n) AS (SELECT 1 FROM (VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) AS v(n)),
     E2(n) AS (SELECT 1 FROM E1 AS a CROSS JOIN E1 AS b),
     E4(n) AS (SELECT 1 FROM E2 AS a CROSS JOIN E2 AS b),
     E8(n) AS (SELECT 1 FROM E4 AS a CROSS JOIN E4 AS b)
INSERT #Numbers WITH (TABLOCK) (n)
SELECT TOP (@Orders) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM E8;

INSERT dbo.Categories (CategoryId, Name)
VALUES (1, N'Books'), (2, N'Electronics'), (3, N'Home'), (4, N'Garden'), (5, N'Toys'),
       (6, N'Sports'), (7, N'Clothing'), (8, N'Shoes'), (9, N'Beauty'), (10, N'Health'),
       (11, N'Grocery'), (12, N'Office'), (13, N'Pet Supplies'), (14, N'Automotive'), (15, N'Music'),
       (16, N'Movies'), (17, N'Games'), (18, N'Tools'), (19, N'Jewelry'), (20, N'Baby');

INSERT dbo.Products WITH (TABLOCK) (ProductId, CategoryId, Sku, Name, UnitPrice, IsActive)
SELECT n.n, c.CategoryId, CONCAT('SKU-', RIGHT(CONCAT('0000', n.n), 5)), CONCAT(c.Name, N' item ', n.n),
       CAST((100 + r.r1 % 49900) / 100.0 AS decimal(10,2)),
       CASE WHEN r.r2 % 100 < 95 THEN 1 ELSE 0 END
FROM #Numbers AS n
CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@Seed, '|product|', n.n))) AS h(h)
CROSS APPLY (SELECT CAST(SUBSTRING(h.h, 1, 4) AS bigint), CAST(SUBSTRING(h.h, 5, 4) AS bigint),
                    CAST(SUBSTRING(h.h, 9, 4) AS bigint)) AS r(r0, r1, r2)
JOIN dbo.Categories AS c ON c.CategoryId = 1 + r.r0 % 20
WHERE n.n <= @Products;

-- Fictional names; emails on reserved example domains only.
INSERT dbo.Customers WITH (TABLOCK) (CustomerId, Email, FirstName, LastName, Country, CreatedAt)
SELECT n.n,
       LOWER(CONCAT(nm.FirstName, '.', nm.LastName, '.', n.n, CASE WHEN r.r2 % 4 = 0 THEN '@example.org' ELSE '@example.com' END)),
       nm.FirstName, nm.LastName,
       CHOOSE(1 + r.r3 % 10, 'US', 'GB', 'DE', 'FR', 'VN', 'AU', 'CA', 'NL', 'SE', 'JP'),
       DATEADD(second, r.r4 % 86400, DATEADD(day, r.r5 % 730, CAST('2021-01-01' AS datetime2(0))))
FROM #Numbers AS n
CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@Seed, '|customer|', n.n))) AS h(h)
CROSS APPLY (SELECT CAST(SUBSTRING(h.h, 1, 4) AS bigint), CAST(SUBSTRING(h.h, 5, 4) AS bigint),
                    CAST(SUBSTRING(h.h, 9, 4) AS bigint), CAST(SUBSTRING(h.h, 13, 4) AS bigint),
                    CAST(SUBSTRING(h.h, 17, 4) AS bigint), CAST(SUBSTRING(h.h, 21, 4) AS bigint)) AS r(r0, r1, r2, r3, r4, r5)
CROSS APPLY (SELECT CHOOSE(1 + r.r0 % 20, N'Alex', N'Sam', N'Jordan', N'Taylor', N'Morgan', N'Casey', N'Riley', N'Jamie',
                           N'Avery', N'Quinn', N'Robin', N'Drew', N'Kai', N'Sky', N'Reese', N'Rowan', N'Emery', N'Finley',
                           N'Hayden', N'Parker'),
                    CHOOSE(1 + r.r1 % 20, N'Ashford', N'Brightwater', N'Coldbrook', N'Dunmore', N'Evergreen', N'Fairhaven',
                           N'Glenwood', N'Hollowell', N'Ironside', N'Juniper', N'Kingsley', N'Larkspur', N'Meadowbrook',
                           N'Northcott', N'Oakhurst', N'Pinecrest', N'Quillfeather', N'Riverton', N'Stonebridge', N'Thornfield')
            ) AS nm(FirstName, LastName)
WHERE n.n <= @Customers;

-- Order dates span 2023-01-01 to 2025-12-31 (1,096 days). TotalAmount is set
-- from the order lines below.
INSERT dbo.Orders WITH (TABLOCK) (OrderId, CustomerId, OrderDate, Status, TotalAmount)
SELECT n.n,
       CASE WHEN r.r0 % 100 < 5 THEN 1 + r.r1 % 10 ELSE 1 + r.r1 % @Customers END,
       DATEADD(second, r.r5 % 86400,
               CASE WHEN r.r2 % 100 < 20
                    THEN DATEADD(day, r.r3 % 61, CAST(DATEFROMPARTS(2023 + r.r4 % 3, 11, 1) AS datetime2(0)))
                    ELSE DATEADD(day, r.r3 % 1096, CAST('2023-01-01' AS datetime2(0))) END),
       CASE WHEN r.r6 % 100 < 70 THEN 'Delivered' WHEN r.r6 % 100 < 80 THEN 'Shipped'
            WHEN r.r6 % 100 < 88 THEN 'Paid'      WHEN r.r6 % 100 < 93 THEN 'Pending'
            WHEN r.r6 % 100 < 98 THEN 'Cancelled' ELSE 'Returned' END,
       0
FROM #Numbers AS n
CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@Seed, '|order|', n.n))) AS h(h)
CROSS APPLY (SELECT CAST(SUBSTRING(h.h, 1, 4) AS bigint), CAST(SUBSTRING(h.h, 5, 4) AS bigint),
                    CAST(SUBSTRING(h.h, 9, 4) AS bigint), CAST(SUBSTRING(h.h, 13, 4) AS bigint),
                    CAST(SUBSTRING(h.h, 17, 4) AS bigint), CAST(SUBSTRING(h.h, 21, 4) AS bigint),
                    CAST(SUBSTRING(h.h, 25, 4) AS bigint)) AS r(r0, r1, r2, r3, r4, r5, r6)
WHERE n.n <= @Orders;

INSERT dbo.OrderItems WITH (TABLOCK) (OrderId, LineNumber, ProductId, Quantity, UnitPrice)
SELECT n.n, l.LineNumber, p.ProductId, CAST(1 + ri.r1 % 4 AS smallint), p.UnitPrice
FROM #Numbers AS n
CROSS APPLY (SELECT 1 + CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lines|', n.n)), 1, 4) AS bigint) % 5) AS lc(LineCount)
JOIN (VALUES (1), (2), (3), (4), (5)) AS l(LineNumber) ON l.LineNumber <= lc.LineCount
CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@Seed, '|item|', n.n, '|', l.LineNumber))) AS h(h)
CROSS APPLY (SELECT CAST(SUBSTRING(h.h, 1, 4) AS bigint), CAST(SUBSTRING(h.h, 5, 4) AS bigint),
                    CAST(SUBSTRING(h.h, 9, 4) AS bigint)) AS ri(r0, r1, r2)
JOIN dbo.Products AS p
  ON p.ProductId = CASE WHEN ri.r0 % 100 < 30 THEN 1 + ri.r2 % 100 ELSE 1 + ri.r2 % @Products END
WHERE n.n <= @Orders;

UPDATE o
SET TotalAmount = t.Total
FROM dbo.Orders AS o
JOIN (SELECT OrderId, SUM(Quantity * UnitPrice) AS Total FROM dbo.OrderItems GROUP BY OrderId) AS t
  ON t.OrderId = o.OrderId;

-- Attempt 1: a failed attempt for 5% of the orders that were not left pending.
-- Attempt 2: the captured payment of every paid order.
INSERT dbo.Payments WITH (TABLOCK) (PaymentId, OrderId, AttemptedAt, Method, Status, Amount)
SELECT ROW_NUMBER() OVER (ORDER BY o.OrderId, a.Attempt), o.OrderId,
       DATEADD(minute, a.Attempt * (1 + r.r1 % 30), o.OrderDate),
       CHOOSE(1 + r.r2 % 3, 'Card', 'BankTransfer', 'Wallet'),
       CASE a.Attempt WHEN 1 THEN 'Failed' ELSE 'Captured' END,
       o.TotalAmount
FROM dbo.Orders AS o
CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@Seed, '|payment|', o.OrderId))) AS h(h)
CROSS APPLY (SELECT CAST(SUBSTRING(h.h, 1, 4) AS bigint), CAST(SUBSTRING(h.h, 5, 4) AS bigint),
                    CAST(SUBSTRING(h.h, 9, 4) AS bigint)) AS r(r0, r1, r2)
CROSS JOIN (VALUES (1), (2)) AS a(Attempt)
WHERE (a.Attempt = 1 AND r.r0 % 100 < 5 AND o.Status <> 'Pending')
   OR (a.Attempt = 2 AND o.Status IN ('Paid', 'Shipped', 'Delivered', 'Returned'));

-- Full-scan statistics on every column, so that estimates and plans do not depend
-- on sampling: sp_createstats adds single-column statistics where none exist yet
-- (otherwise SQL Server creates them later, sampled, when a query first needs
-- them), then every statistic is rebuilt from all rows.
EXEC sys.sp_createstats @indexonly = 'NO', @fullscan = 'FULLSCAN';
UPDATE STATISTICS dbo.Categories WITH FULLSCAN;
UPDATE STATISTICS dbo.Products WITH FULLSCAN;
UPDATE STATISTICS dbo.Customers WITH FULLSCAN;
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;
UPDATE STATISTICS dbo.OrderItems WITH FULLSCAN;
UPDATE STATISTICS dbo.Payments WITH FULLSCAN;

INSERT dbo.LabInfo (LabInfoId, Seed, Scale, GeneratedAt) VALUES (1, @Seed, @Scale, SYSUTCDATETIME());

SELECT t.TableName, t.RowCnt
FROM (VALUES (1, 'Categories', (SELECT COUNT_BIG(*) FROM dbo.Categories)),
             (2, 'Products',   (SELECT COUNT_BIG(*) FROM dbo.Products)),
             (3, 'Customers',  (SELECT COUNT_BIG(*) FROM dbo.Customers)),
             (4, 'Orders',     (SELECT COUNT_BIG(*) FROM dbo.Orders)),
             (5, 'OrderItems', (SELECT COUNT_BIG(*) FROM dbo.OrderItems)),
             (6, 'Payments',   (SELECT COUNT_BIG(*) FROM dbo.Payments))) AS t(SortKey, TableName, RowCnt)
ORDER BY t.SortKey;
PRINT CONCAT(N'Generated seed ', @Seed, N', scale ', @Scale, N' in ',
             DATEDIFF(second, @Start, SYSDATETIME()), N' s.');
GO
