/*
    Case 1 index: supports the join on CustomerId and the OrderDate range.

    Key order: CustomerId first because the query filters it by equality, then
    OrderDate for the range, which also returns rows already sorted by date.
    Status and TotalAmount are included so the query needs no key lookup.

    Safe to re-run. sqlcmd variables: DatabaseName.
*/
:on error exit
SET NOCOUNT ON;
USE [$(DatabaseName)];

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.Orders') AND name = N'IX_Orders_CustomerId_OrderDate')
    CREATE INDEX IX_Orders_CustomerId_OrderDate
        ON dbo.Orders (CustomerId, OrderDate)
        INCLUDE (Status, TotalAmount);
