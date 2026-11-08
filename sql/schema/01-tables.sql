/*
    Creates the order-management tables. Safe to re-run: existing tables are kept.

    The schema starts with primary keys, foreign keys and the unique email
    constraint only. Each case study adds the indexes it needs, so that their
    effect can be measured in isolation. Foreign keys do not get supporting
    indexes on purpose: SQL Server does not create them automatically, and the
    missing ones are part of what the case studies diagnose.

    sqlcmd variables: DatabaseName (see 00-setup/01-create-database.sql).
*/
:on error exit
SET NOCOUNT ON;
USE [$(DatabaseName)];
GO

IF OBJECT_ID(N'dbo.LabInfo', N'U') IS NULL
CREATE TABLE dbo.LabInfo (
    LabInfoId   tinyint       NOT NULL CONSTRAINT PK_LabInfo PRIMARY KEY CONSTRAINT CK_LabInfo_SingleRow CHECK (LabInfoId = 1),
    Seed        int           NOT NULL,
    Scale       int           NOT NULL,
    GeneratedAt datetime2(0)  NOT NULL
);

IF OBJECT_ID(N'dbo.Categories', N'U') IS NULL
CREATE TABLE dbo.Categories (
    CategoryId  int           NOT NULL CONSTRAINT PK_Categories PRIMARY KEY,
    Name        nvarchar(50)  NOT NULL
);

IF OBJECT_ID(N'dbo.Products', N'U') IS NULL
CREATE TABLE dbo.Products (
    ProductId   int           NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
    CategoryId  int           NOT NULL CONSTRAINT FK_Products_Categories REFERENCES dbo.Categories (CategoryId),
    Sku         varchar(20)   NOT NULL,
    Name        nvarchar(100) NOT NULL,
    UnitPrice   decimal(10,2) NOT NULL,
    IsActive    bit           NOT NULL
);

-- Email is varchar, as in many older schemas; .NET sends string parameters as
-- nvarchar by default. Case 1 is built on that mismatch.
IF OBJECT_ID(N'dbo.Customers', N'U') IS NULL
CREATE TABLE dbo.Customers (
    CustomerId  int           NOT NULL CONSTRAINT PK_Customers PRIMARY KEY,
    Email       varchar(254)  NOT NULL CONSTRAINT UQ_Customers_Email UNIQUE,
    FirstName   nvarchar(50)  NOT NULL,
    LastName    nvarchar(50)  NOT NULL,
    Country     char(2)       NOT NULL,
    CreatedAt   datetime2(0)  NOT NULL
);

IF OBJECT_ID(N'dbo.Orders', N'U') IS NULL
CREATE TABLE dbo.Orders (
    OrderId     int           NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
    CustomerId  int           NOT NULL CONSTRAINT FK_Orders_Customers REFERENCES dbo.Customers (CustomerId),
    OrderDate   datetime2(0)  NOT NULL,
    Status      varchar(10)   NOT NULL,
    TotalAmount decimal(12,2) NOT NULL
);

IF OBJECT_ID(N'dbo.OrderItems', N'U') IS NULL
CREATE TABLE dbo.OrderItems (
    OrderId     int           NOT NULL CONSTRAINT FK_OrderItems_Orders REFERENCES dbo.Orders (OrderId),
    LineNumber  tinyint       NOT NULL,
    ProductId   int           NOT NULL CONSTRAINT FK_OrderItems_Products REFERENCES dbo.Products (ProductId),
    Quantity    smallint      NOT NULL,
    UnitPrice   decimal(10,2) NOT NULL,
    CONSTRAINT PK_OrderItems PRIMARY KEY (OrderId, LineNumber)
);

-- Payment attempts. No card data of any kind, not even masked numbers.
IF OBJECT_ID(N'dbo.Payments', N'U') IS NULL
CREATE TABLE dbo.Payments (
    PaymentId   int           NOT NULL CONSTRAINT PK_Payments PRIMARY KEY,
    OrderId     int           NOT NULL CONSTRAINT FK_Payments_Orders REFERENCES dbo.Orders (OrderId),
    AttemptedAt datetime2(0)  NOT NULL,
    Method      varchar(12)   NOT NULL,
    Status      varchar(10)   NOT NULL,
    Amount      decimal(12,2) NOT NULL
);
GO
