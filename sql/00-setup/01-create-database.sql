/*
    Creates the lab database if it does not exist and applies the lab settings.
    With Reset=1 it first drops the database, so every object and row is lost.
    Safe to re-run: with Reset=0 an existing database is kept.

    sqlcmd variables (both required):
      DatabaseName  letters, digits and underscores only
      Reset         1 = drop and recreate, 0 = keep an existing database

    Example:
      sqlcmd -S localhost -E -C -b -i sql/00-setup/01-create-database.sql -v DatabaseName=PerfLab Reset=0

    The collation is pinned instead of inherited from the instance so that
    string comparison, sort order and implicit-conversion behavior are the same
    on every machine. The implicit-conversion case depends on it: with a SQL
    collation, comparing a varchar column to an nvarchar value prevents an
    index seek.
*/
:on error exit
SET NOCOUNT ON;
USE master;

IF N'$(DatabaseName)' = N'' OR N'$(DatabaseName)' LIKE N'%[^A-Za-z0-9_]%'
    THROW 50001, N'DatabaseName must contain only letters, digits and underscores.', 1;
IF N'$(DatabaseName)' IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 50002, N'DatabaseName must not be a system database.', 1;
IF N'$(Reset)' NOT IN (N'0', N'1')
    THROW 50003, N'Reset must be 0 or 1.', 1;
GO

IF N'$(Reset)' = N'1' AND DB_ID(N'$(DatabaseName)') IS NOT NULL
BEGIN
    ALTER DATABASE [$(DatabaseName)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$(DatabaseName)];
    IF DB_ID(N'$(DatabaseName)') IS NULL
        PRINT N'Dropped database $(DatabaseName).';
END;
GO

-- A failed statement does not stop the rest of its batch, so report success
-- only when the database really exists.
IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    CREATE DATABASE [$(DatabaseName)] COLLATE SQL_Latin1_General_CP1_CI_AS;
    IF DB_ID(N'$(DatabaseName)') IS NOT NULL
        PRINT N'Created database $(DatabaseName).';
END
ELSE
    PRINT N'Database $(DatabaseName) already exists; kept.';
GO

-- A database closed by AUTO_CLOSE reports a NULL collation, so open it first
-- and treat NULL as a mismatch.
USE [$(DatabaseName)];
IF ISNULL(CAST(DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS sysname), N'') <> N'SQL_Latin1_General_CP1_CI_AS'
    THROW 50004, N'The existing database has a different collation. Re-run with Reset=1.', 1;
GO

-- AUTO_CLOSE is on by default in Express and LocalDB; it empties the cache
-- between connections and distorts measurements.
-- SIMPLE recovery keeps the log small while the generator loads millions of rows.
-- Query Store is a second measurement source for the benchmark harness.
ALTER DATABASE [$(DatabaseName)] SET AUTO_CLOSE OFF;
ALTER DATABASE [$(DatabaseName)] SET RECOVERY SIMPLE;
ALTER DATABASE [$(DatabaseName)] SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);
GO

USE master;
SELECT
    name                 AS database_name,
    collation_name,
    compatibility_level,
    recovery_model_desc  AS recovery_model,
    is_auto_close_on,
    is_query_store_on
FROM sys.databases
WHERE name = N'$(DatabaseName)';
GO
