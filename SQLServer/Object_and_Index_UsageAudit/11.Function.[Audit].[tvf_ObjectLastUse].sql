USE [DB_Name]
GO


CREATE FUNCTION [Audit].[tvf_ObjectLastUse] ()
RETURNS TABLE 
AS 
RETURN
           SELECT DBName, SchemaName AS ObjectSchema, TableName AS ObjectName, 
				  (SELECT MAX(v)
					FROM (VALUES (LastUserScan),(LastUserSeek),(LastUserLookup),(LastUserUpdate)) AS value(v)) AS LastUseDate
			FROM [Audit].TableScan
			UNION
			SELECT DBName, SchemaName AS ObjectSchema, ObjectName,
				   LastExecutionDate AS LastUseDate
			FROM [Audit].ObjectExecution




GO


