/*
    Removes the case 1 index, returning dbo.Orders to the lab's baseline schema.
    Safe to re-run. sqlcmd variables: DatabaseName.
*/
:on error exit
SET NOCOUNT ON;
USE [$(DatabaseName)];

DROP INDEX IF EXISTS IX_Orders_CustomerId_OrderDate ON dbo.Orders;
