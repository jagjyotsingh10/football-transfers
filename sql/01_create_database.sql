/* =====================================================================
   Football Transfer ROI  |  Step 1 of 4: create database and schemas
   ---------------------------------------------------------------------
   Run in SSMS, connected to your local SQL Server Express instance.

   Two schemas keep raw data and clean data apart:
     stg = raw CSV text, loaded exactly as downloaded (step 2)
     dw  = typed, filtered, keyed star schema for analysis (step 3)
   ===================================================================== */

IF DB_ID('FootballTransferROI') IS NULL
    CREATE DATABASE FootballTransferROI;
GO

USE FootballTransferROI;
GO

IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('dw')  IS NULL EXEC('CREATE SCHEMA dw');
GO

PRINT 'Database FootballTransferROI is ready with schemas stg and dw.';
