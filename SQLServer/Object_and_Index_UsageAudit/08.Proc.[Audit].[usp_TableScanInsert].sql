USE [DbMaintenance]
GO

/****** Object:  StoredProcedure [Audit].[usp_TableScanInsert]    Script Date: 6/16/2021 4:17:57 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE   PROCEDURE [Audit].[usp_TableScanInsert] @TestMode BIT = NULL
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 7/30/2019 
 Description: 
	 - Logs Last Scan/Seek info for tables in User databases:
	 - This is used as part of a grooming/clean up process for invalid and unused objects
	 - If TestMode IS NULL DEFAULT 0
 Modification: 
  LEFT JOIN sys.objects where type= 'U' to get all tables on initial run
		 On merge insert If dates are NULL (no stats) set to getdate() to estabilsh 
		 initial baseline for groom process to use down stream
  Add IsNoStatDefaultDate flag to Audit.TableScan Table
  Add LastUserUpdate.  Was missing metric.  
 
 exec Audit.usp_TableScanInsert @TestMode = 1
 exec Audit.usp_TableScanInsert @TestMode = 0
 select * from Audit.TableScan
=========================================================================================== */
BEGIN 
	SET NOCOUNT ON; 
	SET ANSI_WARNINGS OFF; 

/*Default TestMode to off when not passed and run code */
IF @TestMode IS NULL 
BEGIN
	SET @TestMode = 0 
END

CREATE TABLE #MySource
    (
      DBName NVARCHAR(128),
      SchemaName NVARCHAR(128),
      TableName NVARCHAR(128),
	  LastUserScan DATETIME,
	  LastUserSeek DATETIME,
	  LastUserLookup DATETIME,
	  LastUserUpdate DATETIME
    )

DECLARE @TableScanQuery NVARCHAR(MAX) =
	'SELECT DB_NAME() AS DBName,
		   s.[name] AS SchemaName,
		   o.[name] AS TableName,
		   MAX(ius.[last_user_scan]) AS LastUserScan,
		   MAX(ius.[last_user_seek]) AS LastUserSeek,
		   MAX(ius.[last_user_lookup]) AS LastUserLookup,
		   MAX(ius.[last_user_update]) AS LastUserUpdate
	FROM sys.objects o
	JOIN sys.schemas s 
		ON o.schema_id = s.schema_id
	LEFT JOIN sys.dm_db_index_usage_stats AS ius
		ON o.object_id = ius.object_id 
	WHERE  o.type = ''U''
	GROUP BY DB_NAME(o.parent_object_id),
			 s.[name],
			 o.[name]'


 DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY FOR   
	SELECT DBName
	FROM [Audit].tvf_GetDatabaseList()
	ORDER BY DBName 
         
	 DECLARE @DB NVARCHAR(128)    
   
	 OPEN curDB    
	 FETCH NEXT FROM curDB INTO @DB    
	 WHILE @@FETCH_STATUS = 0    
		BEGIN  
		
		DECLARE @TUsageSQL NVARCHAR(MAX) = 'USE [' + @DB +']; ' + @TableScanQuery
		
		BEGIN TRY  
				 
			INSERT  INTO #MySource
			( 
				DBName,
				SchemaName,
				TableName,
				LastUserScan,
				LastUserSeek,
				LastUserLookup,
				LastUserUpdate
			)
		    EXEC(@TUsageSQL)  

		 END TRY  
		 BEGIN CATCH

			 IF @@TRANCOUNT > 0
				ROLLBACK TRAN

			 PRINT 'ERROR on curDB (Get Table Scan data) for database '+ @DB;

		 END CATCH  
	 FETCH NEXT FROM curDB INTO @DB    
		END   
        
	 CLOSE curDB    
	DEALLOCATE curDB  

IF @TestMode = 0
BEGIN

	MERGE [Audit].TableScan AS MyTarget
	USING #MySource
	ON #MySource.DBName = MyTarget.DBName
		AND #MySource.SchemaName = MyTarget.SchemaName
		AND #MySource.TableName = MyTarget.TableName
	WHEN MATCHED THEN
		UPDATE SET 
			MyTarget.LastUserScan = ISNULL(#MySource.LastUserScan, MyTarget.LastUserScan),
			MyTarget.LastUserSeek = ISNULL(#MySource.LastUserSeek, MyTarget.LastUserSeek),
			MyTarget.LastUserLookup = ISNULL(#MySource.LastUserLookup, MyTarget.LastUserLookup),
			MyTarget.LastUserUpdate = ISNULL(#MySource.LastUserUpdate, MyTarget.LastUserUpdate),
			MyTarget.IsNoStatDefaultDate = CASE WHEN #MySource.LastUserScan IS NULL 
												AND #MySource.LastUserSeek IS NULL 
												AND #MySource.LastUserLookup IS NULL 
												AND #MySource.LastUserUpdate IS NULL 
												AND MyTarget.IsNoStatDefaultDate = 1 
												THEN 1 ELSE 0 END,
			MyTarget.ModifyDate = GETDATE()
	WHEN NOT MATCHED THEN
		INSERT ( 
				 DBName,
				 SchemaName,
				 TableName,
				 LastUserScan,
				 LastUserSeek,
				 LastUserLookup,
				 LastUserUpdate,
				 IsNoStatDefaultDate,
				 InsertDate,
				 ModifyDate
			   )
		VALUES ( #MySource.DBName ,
				 #MySource.SchemaName ,
				 #MySource.TableName ,
				 ISNULL(#MySource.LastUserScan, GETDATE()),
				 ISNULL(#MySource.LastUserSeek, GETDATE()),
				 ISNULL(#MySource.LastUserLookup, GETDATE()),
				 ISNULL(#MySource.LastUserUpdate, GETDATE()),
				 CASE WHEN #MySource.LastUserScan IS NULL AND #MySource.LastUserSeek IS NULL AND #MySource.LastUserLookup IS NULL AND #MySource.LastUserUpdate IS NULL THEN 1 ELSE 0 END,
				 GETDATE(),
				 GETDATE()				 
			   );

END

IF @TestMode = 1
BEGIN
	SELECT 
		MySource.DBName,
		MySource.SchemaName,
		MySource.TableName,
		COALESCE(MySource.LastUserScan, MyTarget.LastUserScan, GETDATE()) AS LastUserScan,
		COALESCE(MySource.LastUserSeek, MyTarget.LastUserSeek, GETDATE()) AS LastUserSeek,
		COALESCE(MySource.LastUserLookup, MyTarget.LastUserLookup, GETDATE()) AS LastUserLookup,
		COALESCE(MySource.LastUserUpdate, MyTarget.LastUserUpdate, GETDATE()) AS LastUserUpdate,
		CASE WHEN MySource.LastUserScan IS NULL 
			 AND MySource.LastUserSeek IS NULL 
			 AND MySource.LastUserLookup IS NULL 
			 AND MySource.LastUserUpdate IS NULL
			 AND ISNULL(MyTarget.IsNoStatDefaultDate,0) = 1
			 THEN 1 ELSE 0 END AS IsNoStatDefaultDate
	FROM #MySource AS MySource
	LEFT JOIN [Audit].TableScan AS MyTarget 
		ON MySource.DBName = MyTarget.DBName
		AND MySource.SchemaName = MyTarget.SchemaName
		AND MySource.TableName = MyTarget.TableName
	--WHERE MyTarget.DBName IS NULL 
	--	AND MyTarget.SchemaName IS NULL 
	--	AND MyTarget.TableName IS NULL
	ORDER BY MySource.DBName, MySource.SchemaName, MySource.TableName
END

END

GO


