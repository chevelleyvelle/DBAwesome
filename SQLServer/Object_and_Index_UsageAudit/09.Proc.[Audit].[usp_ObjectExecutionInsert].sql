USE [DB_Name]
GO


CREATE PROCEDURE [Audit].[usp_ObjectExecutionInsert]
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 7/30/2019 
 Description: 
	 - Logs Last Execution Date for objects in User databases:
	 - This is used as part of a grooming/clean up process for invalid and unused objects
 Modification: 
  [DS-6150] LEFT JOIN sys.objects where type= 'P' to get all stored procs on initial run
		 On merge insert If dates are NULL (no stats) set to getdate() to estabilsh 
		 initial baseline for groom process to use down stream
  [DS-6259] Added where type = 'FN' and pull from sys.dm_exec_function_stats so we have 
		 Scalar Function stats.
  [DS6360] Add IsNoStatDefaultDate flag to Audit.ObjectExecution Table
 exec Audit.usp_ObjectExecutionInsert
 select * from Audit.ObjectExecution
=========================================================================================== */
BEGIN 
	SET NOCOUNT ON;
	SET ANSI_WARNINGS OFF; 

CREATE TABLE #MySource
    (
      DBName SYSNAME,
      SchemaName VARCHAR(25),
      ObjectName VARCHAR(250),
      ObjectType VARCHAR(50),
	  LastExecutionDate DATETIME
    )
INSERT  INTO #MySource
        ( DBName,
          SchemaName,
          ObjectName,
		  ObjectType,
		  LastExecutionDate
        )
EXEC sp_MSforeachdb 'USE ? 
SELECT DB_NAME() AS DBName,
	ss.name AS SchemaName,
	OBJECT_NAME(o.[object_id]) AS ObjectName,
	o.type_desc AS ObjectType,
	MAX(s.last_execution_time) AS LastExecutionDate
FROM  sys.objects o
LEFT JOIN sys.dm_exec_procedure_stats s  ON o.object_id = s.object_id 
	INNER JOIN sys.schemas ss ON o.schema_id = ss.schema_id
WHERE o.type = ''P''
	AND DB_NAME() NOT IN ( ''master'', ''tempdb'', ''msdb'',''model'')
GROUP BY ss.name, OBJECT_NAME(o.[object_id]), o.type_desc
UNION 
SELECT DB_NAME() AS DBName,
	ss.name AS SchemaName,
	OBJECT_NAME(o.[object_id]) AS ObjectName,
	o.type_desc AS ObjectType,
	MAX(s.last_execution_time) AS LastExecutionDate
FROM  sys.objects o
LEFT JOIN sys.dm_exec_function_stats s  ON o.object_id = s.object_id 
	INNER JOIN sys.schemas ss ON o.schema_id = ss.schema_id
WHERE o.type = ''FN''
	AND DB_NAME() NOT IN ( ''master'', ''tempdb'', ''msdb'',''model'')
GROUP BY ss.name, OBJECT_NAME(o.[object_id]), o.type_desc'

MERGE Audit.ObjectExecution AS MyTarget
USING #MySource
ON #MySource.DBName = MyTarget.DBName
    AND #MySource.SchemaName = MyTarget.SchemaName
    AND #MySource.ObjectName = MyTarget.ObjectName
WHEN MATCHED THEN
    UPDATE SET 
		MyTarget.LastExecutionDate = ISNULL(#MySource.LastExecutionDate,MyTarget.LastExecutionDate),
		MyTarget.IsNoStatDefaultDate = CASE WHEN #MySource.LastExecutionDate IS NULL AND MyTarget.IsNoStatDefaultDate = 1 THEN 1 ELSE 0 END
WHEN NOT MATCHED THEN
    INSERT ( DBName,
             SchemaName,
             ObjectName,
             ObjectType,
			 LastExecutionDate,
			 IsNoStatDefaultDate
           )
    VALUES ( #MySource.DBName ,
             #MySource.SchemaName ,
             #MySource.ObjectName ,
             #MySource.ObjectType,
			 ISNULL(#MySource.LastExecutionDate, GETDATE()),
			 CASE WHEN #MySource.LastExecutionDate IS NULL THEN 1 ELSE 0 END
           );


DROP TABLE #MySource

END

GO


