USE DbMaintenance
GO

/* 
	Pulls current index usage where 0 seeks, 0 scans, and 0 lookups where index is not already deleted
	Pulls sum of all usage per index in the history table where all history of the index shows 0 usage.
	Joins current indexes to this summed history for final evaluation.
	Helpful to evaluate indexes that possibly can be removed.
*/

/* PULL ALL CURRENT INDEXES WHERE NOT USER SEEKS,SCANS, LOOKUPS */
SELECT dbname, SchemaName, TableName,
IndexName, IndexColumns, IncludeColumns, IndexFilter, IndexType, 
IsDisabled, IsCompressed, CompressionDescription, IndexSizeKB,
LobDataSizeKB, [RowCount], TotalSeeks, TotalScans, TotalLookups, TotalUpdates,
LastUserSeek, LastUserScan, LastUserLookup, LastUserUpdate,
IsPrimaryKey, IsClustered, IsUnique, IsUniqueConstraint, IsDeleted
INTO #current
FROM Audit.IndexUsage
WHERE totalSeeks = 0 AND TotalScans = 0 AND TotalLookups = 0
AND IsDeleted = 0
ORDER BY IndexColumns, IncludeColumns, IndexFilter

/* GET SUM OF ALL USAGE FROM ALL HISTORY and PULL WHERE NO USER SEEKS,SCANS, LOOKUPS */
;WITH HistoryCTE AS (
SELECT dbname, SchemaName, TableName,
IndexName, SUM(TotalSeeks) AS TotalSeeksHistory, SUM(TotalScans) AS TotalScansHistory, SUM(TotalLookups) AS TotalLookupsHistory, SUM(TotalUpdates) AS TotalUpdatesHistory,
MIN(SQLRestartDate) AS EarliestHistRestartDate
FROM Audit.IndexUsageHistory
GROUP BY dbname, SchemaName, TableName, IndexName
)
SELECT hcte.DBName,
       hcte.SchemaName,
       hcte.TableName,
       hcte.IndexName,
	   hist.IndexColumns, 
	   hist.IncludeColumns, 
	   hist.IndexFilter, 
	   hist.IndexType,
	   hist.IsDisabled, 
	   hist.IsCompressed, 
	   hist.CompressionDescription, 
	   hist.IndexSizeKB,
	   hist.LobDataSizeKB, 
	   hist.[RowCount],	   
       hcte.TotalSeeksHistory,
       hcte.TotalScansHistory,
       hcte.TotalLookupsHistory,
       hcte.TotalUpdatesHistory,
	   hist.IsPrimaryKey, 
	   hist.IsClustered, 
	   hist.IsUnique, 
	   hist.IsUniqueConstraint, 
	   hist.IsDeleted,
	   hcte.EarliestHistRestartDate
INTO #history
FROM HistoryCTE hcte
JOIN 
(SELECT h.DBName, h.SchemaName, h.TableName, h.IndexName, h.IndexColumns, h.IncludeColumns, h.IndexFilter, h.IndexType, h.IsDisabled, 
	   h.IsCompressed, h.CompressionDescription, h.IndexSizeKB,h.LobDataSizeKB, h.[RowCount],	   
	h.IsPrimaryKey, h.IsClustered, h.IsUnique, h.IsUniqueConstraint, h.IsDeleted,
	ROW_NUMBER() OVER(PARTITION BY h.DBName, h.SchemaName, h.TableName, h.IndexName ORDER BY h.HistoryInsertDate DESC) AS RowNum
 FROM Audit.IndexUsageHistory h 
 ) hist 
 ON hist.DBName = hcte.DBName AND hist.SchemaName = hcte.SchemaName AND hist.TableName = hcte.TableName AND hist.IndexName = hcte.IndexName AND hist.RowNum = 1
WHERE hcte.TotalSeeksHistory = 0 AND hcte.TotalScansHistory = 0 AND hcte.TotalLookupsHistory = 0


SELECT
c.dbname, c.SchemaName, c.TableName,
c.indexname, c.IndexColumns, c.IncludeColumns, c.IndexFilter, c.IndexType, c.IndexSizeKB,--c.IndexSizekb/1024 AS IndexSizeMB,
c.IsDisabled, 
c.IsCompressed,
c.CompressionDescription,
c.LobDataSizeKb,
c.[RowCount],
c.TotalSeeks, h.TotalSeeksHistory,
c.TotalScans, h.TotalScansHistory,
c.TotalLookups, h.TotalLookupsHistory,
c.TotalUpdates, h.TotalUpdatesHistory,
c.LastUserSeek, 
c.LastUserScan, 
c.LastUserLookup, 
c.LastUserUpdate,
c.IsPrimaryKey, c.IsClustered, c.IsUnique, c.IsUniqueConstraint, h.EarliestHistRestartDate
FROM #history h
JOIN #current c 
ON h.dbname = c.dbname AND h.SchemaName = c.SchemaName AND h.TableName = c.TableName AND h.IndexName = c.IndexName
WHERE c.IsPrimaryKey=0 AND  c.IsClustered = 0 AND c.IsUnique = 0 AND c.IsUniqueConstraint = 0 ---If looking for only nc/non-unique indexes unused. 


--DROP TABLE #history
--DROP TABLE #current



--/*2014 version*/
----EXEC DbMaintenance.dbo.sp_BlitzIndex @DatabaseName='Reporting', @SchemaName='rpd', @TableName='Encounter';