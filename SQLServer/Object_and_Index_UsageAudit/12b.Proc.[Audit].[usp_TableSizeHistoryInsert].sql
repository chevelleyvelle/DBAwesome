USE [DbMaintenance]
GO

CREATE OR ALTER PROCEDURE [Audit].[usp_TableSizeHistoryInsert] @HistoryRetentionMonths INT = NULL, @TestMode BIT = NULL
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 2/22/2022
 Last Modified:  4/21/2022
 Description: 
	 - Log all Tables with sizes and row counts in non-excluded databases to a table in the DBA Team Database
	 - This will be used in future analysis
	 - Retention defaults to NULL (Don't delete history).  Will delete history older than what is passed in if not NULL.
	 - Parameters: @TestMode = 1 Print what would be logged without logging to table
							  NULLable.  If NULL Default 0
				  @HistoryRetentionMonths NULLable.  If NULL Default keep all history.
							  Used for history of [Audit].IndexUsageHistory

	 - Original Source reference for query to pull data
	 --https://www.mssqltips.com/sqlservertip/5701/get-sql-server-row-count-and-space-used-with-the-sprows/

	 -Does not include space for Memory Optimized Data Storage (2017 and up) to support older versions of SQL.

 EXEC [Audit].[usp_TableSizeHistoryInsert] @HistoryRetentionMonths= NULL, @TestMode = 1
 EXEC [Audit].[usp_TableSizeHistoryInsert] @HistoryRetentionMonths= 18, @TestMode = 0
 SELECT * FROM [Audit].[TableSizeHistory]
=========================================================================================== */
BEGIN 
	SET NOCOUNT ON;

/*Default TestMode to off when not passed and run code */
IF @TestMode IS NULL 
BEGIN
	SET @TestMode = 0 
END

/* Proc Variables */

DECLARE @DatabaseName NVARCHAR(128)
DECLARE @SchemaName NVARCHAR(128)
DECLARE @TableName NVARCHAR(128)
DECLARE @FullTableName nvarchar(776) /* Matches sp_spaceUsed @ObjName param */
DECLARE @TableListQuery NVARCHAR(MAX)
DECLARE @TableSizeQuery NVARCHAR(MAX)
DECLARE @TableSizeParams NVARCHAR(MAX)
DECLARE @QueryParamFullTableName NVARCHAR(1000)

SET @TableSizeParams = N'@FullTableName nvarchar(776)'
SET @QueryParamFullTableName = N'@FullTableName'

/* Create Temp table(s)*/
CREATE TABLE #TableList
	(
		[DbName] NVARCHAR(128),
		[SchemaName] NVARCHAR(128),
		[TableName] NVARCHAR(128)
	);

CREATE TABLE #CurResults
	(
		[name] NVARCHAR(128),
        [rows] BIGINT,
        [reserved] NVARCHAR(80),
        [data] NVARCHAR(80),
        [index_size] NVARCHAR(80),
        [unused] NVARCHAR(80)
	);

IF @TestMode = 1
BEGIN
	CREATE TABLE #TempResults 
	(
		[DBName] [NVARCHAR](128) NOT NULL,
		[SchemaName] [NVARCHAR](128) NULL,
		[TableName] [NVARCHAR](128) NULL,
		[RowCount] [BIGINT] NULL,
		[ReservedSpaceKB] [BIGINT] NULL,
		[DataSpaceKB] [BIGINT] NULL,
		[IndexSpaceKB] [BIGINT] NULL,
		[UnusedSpaceKB] [BIGINT] NULL,
		[InsertDate] [DATETIME] NOT NULL
	)
END

/* Get database list and open cursor process through each database*/
DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY FOR   
	SELECT DBName
	FROM [Audit].tvf_GetDatabaseList()
	ORDER BY DBName  
   
	 OPEN curDB    
	 FETCH NEXT FROM curDB INTO @DatabaseName    
	 WHILE @@FETCH_STATUS = 0    
		BEGIN  

			SET @TableListQuery = N'USE [' + @DatabaseName +'];' + CHAR(13) +
			N'SELECT DB_NAME() AS DbName, s.name AS SchemaName, o.name AS TableName
			  FROM sys.schemas s
			  INNER JOIN sys.objects o ON s.schema_id = o.schema_id
			  WHERE o.type = ''U''
				AND o.name <> ''sysdiagrams''
				AND o.is_ms_shipped = 0'
		
		BEGIN TRY
		
			INSERT INTO #TableList
			(DbName, SchemaName, TableName)
			EXECUTE sp_executesql @TableListQuery

		END TRY  
		BEGIN CATCH

			IF @@TRANCOUNT > 0
				ROLLBACK TRAN

			PRINT 'ERROR on curDB (Get Table Size History) for database '+ @DatabaseName;

		END CATCH  
	 FETCH NEXT FROM curDB INTO @DatabaseName    
		END   
        
	 CLOSE curDB    
	 DEALLOCATE curDB  

/* Get table list and open cursor process through each database and table*/
DECLARE curTables CURSOR LOCAL STATIC FORWARD_ONLY FOR   
	SELECT DBName, SchemaName, TableName
	FROM #TableList
	ORDER BY DBName, SchemaName, TableName  
   
	OPEN curTables    
	FETCH NEXT FROM curTables INTO @DatabaseName, @SchemaName, @TableName    
	WHILE @@FETCH_STATUS = 0    
		BEGIN  

			SET @FullTableName = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName)

			SET @TableSizeQuery = N'USE [' + @DatabaseName +'];' + CHAR(13) + 
			N'exec sp_spaceused @ObjName = ' + @QueryParamFullTableName + N';'

		BEGIN TRY  

			INSERT INTO #CurResults
			(name, rows, reserved, data, index_size, unused)
			EXECUTE sp_executesql @TableSizeQuery, @TableSizeParams, @FullTableName = @FullTableName

			IF @TestMode = 0
			BEGIN
				/* Insert into logging table */
				INSERT INTO [Audit].TableSizeHistory
				(
					DBName,
					SchemaName,
					TableName,
					[RowCount],
					ReservedSpaceKB,
					DataSpaceKB,
					IndexSpaceKB,
					UnusedSpaceKB,
					InsertDate
				)
				SELECT @DatabaseName,
					   @SchemaName,
					   @TableName,
					   [rows] AS [RowCount],
					  CAST(LEFT(reserved, LEN(reserved) - 3) AS BIGINT) AS ReservedSpaceKB, /* Remove KB from results leaving the bigint */
					  CAST(LEFT([data], LEN([data]) - 3) AS BIGINT) AS DataSpaceKB, /* Remove KB from results leaving the bigint */
					  CAST(LEFT(index_size, LEN(index_size) - 3) AS BIGINT) AS IndexSpaceKB, /* Remove KB from results leaving the bigint */
					  CAST(LEFT(unused, LEN(unused) - 3) AS BIGINT) AS UnusedSpaceKB, /* Remove KB from results leaving the bigint */
					  GETDATE() AS InsertDate
				FROM #CurResults
			END
			ELSE 
			BEGIN
				/* Test mode - no insert into logging table */
				INSERT INTO #TempResults
				(
					DBName,
					SchemaName,
					TableName,
					[RowCount],
					ReservedSpaceKB,
					DataSpaceKB,
					IndexSpaceKB,
					UnusedSpaceKB,
					InsertDate
				)
				SELECT @DatabaseName,
					   @SchemaName,
					   @TableName,
					   [rows] AS [RowCount],
					  CAST(LEFT(reserved, LEN(reserved) - 3) AS BIGINT) AS ReservedSpaceKB, /* Remove KB from results leaving the bigint */
					  CAST(LEFT([data], LEN([data]) - 3) AS BIGINT) AS DataSpaceKB, /* Remove KB from results leaving the bigint */
					  CAST(LEFT(index_size, LEN(index_size) - 3) AS BIGINT) AS IndexSpaceKB, /* Remove KB from results leaving the bigint */
					  CAST(LEFT(unused, LEN(unused) - 3) AS BIGINT) AS UnusedSpaceKB, /* Remove KB from results leaving the bigint */
					  GETDATE() AS InsertDate
				FROM #CurResults
			END
			
		/* Truncate table between databases as to not double insert values into #CurResultsParsed */
		TRUNCATE TABLE #CurResults 
		
		END TRY  
		BEGIN CATCH

			IF @@TRANCOUNT > 0
				ROLLBACK TRAN

			PRINT 'ERROR on curTables (Get Table Size History) for database '+ @DatabaseName + '.' + @FullTableName;

		END CATCH  
	FETCH NEXT FROM curTables INTO @DatabaseName, @SchemaName, @TableName   
		END   
        
	CLOSE curTables    
	DEALLOCATE curTables  

IF @TestMode = 1
BEGIN
	SELECT DBName,
           SchemaName,
           TableName,
           [RowCount],
           ReservedSpaceKB,
           DataSpaceKB,
           IndexSpaceKB,
           UnusedSpaceKB,
           InsertDate
	FROM #TempResults
END

/* Remove history past retention */
IF @TestMode = 0 AND (@HistoryRetentionMonths IS NOT NULL OR @HistoryRetentionMonths <> 0)
BEGIN
	DELETE
	FROM Audit.TableSizeHistory
	WHERE InsertDate < DATEADD(MONTH,-@HistoryRetentionMonths,GETDATE())
END

END
GO

