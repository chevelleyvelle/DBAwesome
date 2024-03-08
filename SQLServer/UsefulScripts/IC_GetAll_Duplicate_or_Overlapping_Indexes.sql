USE DbMaintenance
GO

---EXACT DUPLICATE INDEXES
SELECT iu.ID,
       iu.DBName,
       iu.ObjectID,
       iu.SchemaName,
       iu.TableName,
       iu.IndexID,
       iu.IndexName,
       iu.IndexColumns,
       iu.IncludeColumns,
       iu.IndexFilter,
       iu.IndexType,
       iu.IsPrimaryKey,
       iu.IsClustered,
       iu.IsUnique,
       iu.IsUniqueConstraint,
       iu.HasFilter,
       iu.IsDisabled,
	   iu.IsCompressed,
	   iu.CompressionDescription,
       iu.IndexSizeKB,
	   iu.LobDataSizeKB,
	   iu.[RowCount],
       iu.TotalSeeks,
       iu.TotalScans,
       iu.TotalLookups,
       iu.TotalUpdates,
       iu.LastUserSeek,
       iu.LastUserScan,
       iu.LastUserLookup,
       iu.LastUserUpdate,
       iu.ExcludeFromCleanup,
       iu.IsDeleted,
       iu.CleanupCommand,
       iu.RollbackCommand,
       iu.InsertDate,
       iu.ModifyDate,
       iu.SQLRestartDate
FROM DbMaintenance.[Audit].IndexUsage iu
JOIN (
	SELECT Dbname, objectid, IndexColumns, IncludeColumns, IndexFilter, COUNT(*) AS dupes
	FROM Audit.IndexUsage
	WHERE IsDeleted = 0
	--AND Dbname = 'MasterIndex'
	GROUP BY Dbname, ObjectID, IndexColumns, IncludeColumns, IndexFilter
	HAVING COUNT(*)>1
) dupe 
ON iu.DBName = dupe.DBName 
AND iu.ObjectID = dupe.objectid 
AND iu.IndexColumns = dupe.IndexColumns 
AND ISNULL(iu.IncludeColumns,'') = ISNULL(dupe.IncludeColumns,'') 
AND ISNULL(iu.indexfilter,'') = ISNULL(dupe.IndexFilter,'')
ORDER BY iu.DBName, iu.SchemaName, iu.TableName, 
  iu.IsPrimaryKey DESC, iu.IsClustered DESC, iu.IsUnique DESC, iu.IsUniqueConstraint DESC


---OVERLAPPING INDEXES First Key Column as a key for overlap
USE DbMaintenance
GO

/* OVERLAPPING INDEXES FIRST KEY COLUMN ONLY */
SELECT iu.ID,
       iu.DBName,
       iu.ObjectID,
       iu.SchemaName,
       iu.TableName,
       iu.IndexID,
       iu.IndexName,
       iu.IndexColumns,
       iu.IncludeColumns,
       iu.IndexFilter,
       iu.IndexType,
       iu.IsPrimaryKey,
       iu.IsClustered,
       iu.IsUnique,
       iu.IsUniqueConstraint,
       iu.HasFilter,
       iu.IsDisabled,
       iu.IsCompressed,
	   iu.CompressionDescription,
       iu.IndexSizeKB,
	   iu.LobDataSizeKB,
	   iu.[RowCount],
       iu.TotalSeeks,
       iu.TotalScans,
       iu.TotalLookups,
       iu.TotalUpdates,
       iu.LastUserSeek,
       iu.LastUserScan,
       iu.LastUserLookup,
       iu.LastUserUpdate,
       iu.ExcludeFromCleanup,
       iu.IsDeleted,
       iu.CleanupCommand,
       iu.RollbackCommand,
       iu.InsertDate,
       iu.ModifyDate,
       iu.SQLRestartDate
FROM DbMaintenance.[Audit].IndexUsage iu
JOIN (
SELECT Dbname, objectid, SUBSTRING(IndexColumns, 1, PATINDEX('%]%', IndexColumns)) FirstKeyColumn, COUNT(*) AS dupes
FROM DbMaintenance.[Audit].IndexUsage
WHERE IsDeleted = 0
GROUP BY Dbname, ObjectID, SUBSTRING(IndexColumns, 1, PATINDEX('%]%', IndexColumns))
HAVING COUNT(*)>1
) dupe 
ON iu.DBName = dupe.DBName 
AND iu.ObjectID = dupe.objectid 
AND SUBSTRING(iu.IndexColumns, 1, PATINDEX('%]%', iu.IndexColumns)) = dupe.FirstKeyColumn
ORDER BY iu.DBName, iu.SchemaName, iu.TableName, iu.IsPrimaryKey DESC, 
  iu.IsClustered DESC, iu.IsUnique DESC, iu.IsUniqueConstraint DESC, iu.IndexColumns