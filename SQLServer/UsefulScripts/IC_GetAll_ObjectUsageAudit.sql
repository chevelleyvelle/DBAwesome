USE DbMaintenance
GO

/*
	Use to help try to find likely unused tables.  Look for where all dates are old.  
	Then do other research into index usage history including and especially on the PK for usage/updates
	Verify with dev on usage and code before attempting to recommend archiving/removing a table.
*/
SELECT DBName, SchemaName, TableName AS ObjectName, 'Table' AS ObjectType, LastUserScan, LastUserSeek, LastUserLookup, NULL AS LastExecutionDate,
  (SELECT MAX(v)
	FROM (VALUES (LastUserScan),(LastUserSeek),(LastUserLookup)) AS value(v)) AS LastObjectUse
FROM Audit.TableScan


/* 
	Last logged used of any object.  **** JUST NOTE THAT PROCS AND FUNCTIONS ARE A BEST GUESS
	Proc and function usage is logged from SQL DMVs for proc cache, which churns a lot and may not capture usage. 
	Use for some research, but cannot be relied upon on if a piece of code hasn't been used to remove.
*/
SELECT DBName, SchemaName, TableName AS ObjectName, 'Table' AS ObjectType, LastUserScan, LastUserSeek, LastUserLookup, NULL AS LastExecutionDate,
  (SELECT MAX(v)
	FROM (VALUES (LastUserScan),(LastUserSeek),(LastUserLookup)) AS value(v)) AS LastObjectUse
  FROM Audit.TableScan
  UNION
  SELECT DBName, SchemaName, ObjectName, ObjectType, NULL AS LastUserScan, NULL AS LastUserSeek, NULL AS LastUserLookup, LastExecutionDate, LastExecutionDate AS LastObjectUse
  FROM Audit.ObjectExecution 