USE [DbMaintenance]
GO

/****** Object:  UserDefinedFunction [Audit].[tvf_ObjectLastUse]    Script Date: 6/16/2021 4:19:06 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
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


