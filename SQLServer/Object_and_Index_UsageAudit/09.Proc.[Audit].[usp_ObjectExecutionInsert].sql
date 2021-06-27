USE [DbMaintenance]
GO

/****** Object:  StoredProcedure [Audit].[usp_ObjectExecutionInsert]    Script Date: 6/16/2021 4:18:19 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE   PROCEDURE [Audit].[usp_ObjectExecutionInsert] @TestMode BIT = NULL
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 7/30/2019 
 Description: 
	 - Logs Last Execution Date for objects in User databases:
	 - This is used as part of a grooming/clean up process for invalid and unused objects
	 - If TestMode IS NULL DEFAULT 0
 Modification: 
  LEFT JOIN sys.objects where type= 'P' to get all stored procs on initial run
		 On merge insert If dates are NULL (no stats) set to getdate() to estabilsh 
		 initial baseline for groom process to use down stream
  Added where type = 'FN' and pull from sys.dm_exec_function_stats so we have 
		 Scalar Function stats.
  Add IsNoStatDefaultDate flag to Audit.ObjectExecution Table

 exec Audit.usp_ObjectExecutionInsert  @TestMode = 1
 exec Audit.usp_ObjectExecutionInsert  @TestMode = 0
 select * from Audit.ObjectExecution
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
      ObjectName NVARCHAR(128),
      ObjectType NVARCHAR(60),
	  LastExecutionDate DATETIME
    )

DECLARE @ObjectUsageQuery NVARCHAR(MAX) =
	'SELECT DB_NAME() AS DBName,
		s.[name] AS SchemaName,
		o.[name] AS ObjectName,
		o.[type_desc] AS ObjectType,
		MAX(ps.last_execution_time) AS LastExecutionDate
	FROM  sys.objects o
	INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
	LEFT JOIN sys.dm_exec_procedure_stats ps  ON o.object_id = ps.object_id 
	WHERE o.[type] = ''P''
	GROUP BY s.[name], o.[name], o.[type_desc]
	UNION 
	SELECT DB_NAME() AS DBName,
		s.[name] AS SchemaName,
		o.[name] AS ObjectName,
		o.[type_desc] AS ObjectType,
		MAX(fs.last_execution_time) AS LastExecutionDate
	FROM  sys.objects o
	INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
	LEFT JOIN sys.dm_exec_function_stats fs  ON o.object_id = fs.object_id 
	WHERE o.type = ''FN''
	GROUP BY s.[name], o.[name], o.[type_desc]'

DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY FOR   
	SELECT DBName
	FROM [Audit].tvf_GetDatabaseList()
	ORDER BY DBName 
         
	 DECLARE @DB NVARCHAR(128)    
   
	 OPEN curDB    
	 FETCH NEXT FROM curDB INTO @DB    
	 WHILE @@FETCH_STATUS = 0    
		BEGIN  
		
		DECLARE @OUsageSQL NVARCHAR(MAX) = 'USE [' + @DB +']; ' + @ObjectUsageQuery
		
		BEGIN TRY  
				 
			INSERT  INTO #MySource
			( 
				DBName,
				SchemaName,
				ObjectName,
				ObjectType,
				LastExecutionDate
			)
		    EXEC(@OUsageSQL)  

		 END TRY  
		 BEGIN CATCH

			 IF @@TRANCOUNT > 0
				ROLLBACK TRAN

			 PRINT 'ERROR on curDB (Get Object Execution data) for database '+ @DB;

		 END CATCH  
	 FETCH NEXT FROM curDB INTO @DB    
		END   
        
	 CLOSE curDB    
	DEALLOCATE curDB  

IF @TestMode = 0
BEGIN

	MERGE Audit.ObjectExecution AS MyTarget
	USING #MySource
	ON #MySource.DBName = MyTarget.DBName
		AND #MySource.SchemaName = MyTarget.SchemaName
		AND #MySource.ObjectName = MyTarget.ObjectName
	WHEN MATCHED THEN
		UPDATE SET 
			MyTarget.LastExecutionDate = ISNULL(#MySource.LastExecutionDate,MyTarget.LastExecutionDate),
			MyTarget.IsNoStatDefaultDate = CASE WHEN #MySource.LastExecutionDate IS NULL AND MyTarget.IsNoStatDefaultDate = 1 THEN 1 ELSE 0 END,
			MyTarget.ModifyDate = GETDATE()
	WHEN NOT MATCHED THEN
		INSERT ( DBName,
				 SchemaName,
				 ObjectName,
				 ObjectType,
				 LastExecutionDate,
				 IsNoStatDefaultDate,
				 InsertDate,
				 ModifyDate
			   )
		VALUES ( #MySource.DBName ,
				 #MySource.SchemaName ,
				 #MySource.ObjectName ,
				 #MySource.ObjectType,
				 ISNULL(#MySource.LastExecutionDate, GETDATE()),
				 CASE WHEN #MySource.LastExecutionDate IS NULL THEN 1 ELSE 0 END,
				 GETDATE(),
				 GETDATE()
			   );

END

IF @TestMode = 1
BEGIN
	SELECT 
		MySource.DBName,
		MySource.SchemaName,
		MySource.ObjectName,
		COALESCE(MySource.LastExecutionDate,MyTarget.LastExecutionDate) AS LastExecutionDate,
		CASE WHEN MySource.LastExecutionDate IS NULL AND ISNULL(MyTarget.IsNoStatDefaultDate,0) = 1 THEN 1 ELSE 0 END AS IsNoStatDefaultDate
	FROM #MySource AS MySource
	LEFT JOIN [Audit].ObjectExecution AS MyTarget 
		ON MySource.DBName = MyTarget.DBName
		AND MySource.SchemaName = MyTarget.SchemaName
		AND MySource.ObjectName = MyTarget.ObjectName
	--WHERE MyTarget.DBName IS NULL 
	--	AND MyTarget.SchemaName IS NULL 
	--	AND MyTarget.TableName IS NULL
	ORDER BY MySource.DBName, MySource.SchemaName, MySource.ObjectName
END

END

GO


