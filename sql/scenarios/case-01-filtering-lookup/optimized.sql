/*
    Case 1 optimized: the same query text, with the email parameter declared with
    the column's type (varchar(254)). In the application this is a one-line change:
    SqlDbType.VarChar with Size 254 instead of AddWithValue. Without the implicit
    conversion SQL Server can seek UQ_Customers_Email.

    Pair it with index-create.sql, which gives dbo.Orders an index for the join
    and the date range.

    sqlcmd variables: DatabaseName, Email, FromDate, ToDate (see benchmark.conf).
*/
SET NOCOUNT ON;
USE [$(DatabaseName)];

EXEC sys.sp_executesql
    N'SELECT o.OrderId, o.OrderDate, o.Status, o.TotalAmount
      FROM dbo.Orders AS o
      JOIN dbo.Customers AS c ON c.CustomerId = o.CustomerId
      WHERE c.Email = @Email
        AND o.OrderDate >= @FromDate AND o.OrderDate < @ToDate
      ORDER BY o.OrderDate DESC, o.OrderId DESC;',
    N'@Email varchar(254), @FromDate datetime2(0), @ToDate datetime2(0)',
    @Email = '$(Email)', @FromDate = '$(FromDate)', @ToDate = '$(ToDate)';
