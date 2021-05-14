USE [DB_Name]
GO


CREATE PROCEDURE [Audit].[usp_TableScanInsert_v2]
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 7/30/2019 
 Description: 
	 - Logs Last Scan/Seek info for tables in User databases:
	 - This is used as part of a grooming/clean up process for invalid and unused objects
 Modification: 
 [DS-6149] LEFT JOIN sys.objects where type= 'U' to get all tables on initial run
		 On merge insert If dates are NULL (no stats) set to getdate() to estabilsh 
		 initial baseline for groom process to use down stream
 [DS-6360] Add IsNoStatDefaultDate flag to Audit.TableScan Table
 [DS-6525] Add LastUserUpdate.  Was missing metric.  Created _v2 proc with this change.
 
 exec Audit.usp_TableScanInsert
 select * from Audit.TableScan
=========================================================================================== */
BEGIN 
	SET NOCOUNT ON; 
	SET ANSI_WARNINGS OFF; 

CREATE TABLE #MySource
    (
      DBName SYSNAME,
      SchemaName VARCHAR(25),
      TableName VARCHAR(250),
	  LastUserScan DATETIME,
	  LastUserSeek DATETIME,
	  LastUserLookup DATETIME,
	  LastUserUpdate DATETIME
    )
INSERT  INTO #MySource
        ( DBName,
          SchemaName,
          TableName,
		  LastUserScan,
		  LastUserSeek,
		  LastUserLookup,
		  LastUserUpdate
        )
EXEC sp_MSforeachdb 'USE ? SELECT DB_NAME() AS DBName,
       ss.name AS SchemaName,
       OBJECT_NAME(o.[object_id]) AS [TableName],
       MAX(ius.[last_user_scan]) AS LastUserScan,
	   MAX(ius.[last_user_seek]) AS LastUserSeek,
	   MAX(ius.[last_user_lookup]) AS LastUserLookup,
	   MAX(ius.[last_user_update]) AS LastUserUpdate
FROM sys.objects o
LEFT JOIN sys.dm_db_index_usage_stats AS ius
    ON o.object_id = ius.object_id 
    INNER JOIN sys.schemas ss
        ON o.schema_id = ss.schema_id
WHERE  o.type = ''U''
	 AND DB_NAME() NOT IN ( ''master'', ''tempdb'', ''msdb'',''model'')
GROUP BY DB_NAME(o.parent_object_id),
         ss.name,
         o.[object_id]'

MERGE Audit.TableScan AS MyTarget
USING #MySource
ON #MySource.DBName = MyTarget.DBName
    AND #MySource.SchemaName = MyTarget.SchemaName
    AND #MySource.TableName = MyTarget.TableName
WHEN MATCHED THEN
    UPDATE SET 
		MyTarget.LastUserScan = ISNULL(#MySource.LastUserScan, MyTarget.LastUserScan),
		MyTarget.LastUserSeek = ISNULL(#MySource.LastUserSeek, MyTarget.LastUserSeek),
		MyTarget.LastUserLookup = ISNULL(#MySource.LastUserLookup, MyTarget.LastUserLookup),
		MyTarget.IsNoStatDefaultDate = CASE WHEN #MySource.LastUserScan IS NULL AND #MySource.LastUserSeek IS NULL AND #MySource.LastUserLookup IS NULL AND #MySource.LastUserUpdate IS NULL AND MyTarget.IsNoStatDefaultDate = 1 THEN 1 ELSE 0 END,
		MyTarget.LastUserUpdate = ISNULL(#MySource.LastUserUpdate, MyTarget.LastUserUpdate)
WHEN NOT MATCHED THEN
    INSERT ( DBName,
             SchemaName,
             TableName,
			 LastUserScan,
			 LastUserSeek,
			 LastUserLookup,
			 IsNoStatDefaultDate,
			 LastUserUpdate
           )
    VALUES ( #MySource.DBName ,
             #MySource.SchemaName ,
             #MySource.TableName ,
			 ISNULL(#MySource.LastUserScan, GETDATE()),
			 ISNULL(#MySource.LastUserSeek, GETDATE()),
			 ISNULL(#MySource.LastUserLookup, GETDATE()),
			 CASE WHEN #MySource.LastUserScan IS NULL AND #MySource.LastUserSeek IS NULL AND #MySource.LastUserLookup IS NULL AND #MySource.LastUserUpdate IS NULL THEN 1 ELSE 0 END,
			 ISNULL(#MySource.LastUserUpdate, GETDATE())
           );


DROP TABLE #MySource

END

GO


