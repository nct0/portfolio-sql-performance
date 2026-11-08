/*
    Case 1 baseline: the customer-service query as the application sends it.

    The application passes the email as a .NET string, which SqlClient sends as
    nvarchar. dbo.Customers.Email is varchar, so SQL Server converts every email
    in the column to nvarchar before comparing (CONVERT_IMPLICIT). With the SQL
    collation of this database that rules out a seek on UQ_Customers_Email.

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
    N'@Email nvarchar(4000), @FromDate datetime2(0), @ToDate datetime2(0)',
    @Email = N'$(Email)', @FromDate = '$(FromDate)', @ToDate = '$(ToDate)';
