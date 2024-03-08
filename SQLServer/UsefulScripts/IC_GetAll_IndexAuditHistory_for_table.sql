USE DbMaintenance 
GO

/*Use this to get all logged history of currently existing indexes on a table*/

/*Index Usage*/
DECLARE @DBName NVARCHAR(128) = 'Registry_001'
DECLARE @SchemaName NVARCHAR(128) = 'dbo'
DECLARE @TableName NVARCHAR(128)= 'SocialHistory'

SELECT dbname, SchemaName, TableName,
IndexName, IndexColumns, IncludeColumns, IndexFilter,
IndexType, IsPrimaryKey, IsUnique, IsDisabled, IsCompressed,
CompressionDescription, IndexSizeKB, LobDataSizeKB, [RowCount],
totalseeks, TotalScans, TotalLookups, TotalUpdates, IsDeleted,
InsertDate, SQLRestartDate, NULL AS HistoryInsertDate, 
CleanupCommand, RollbackCommand
FROM DbMaintenance.audit.IndexUsage
WHERE DBName = @DBName AND SchemaName = @SchemaName AND TableName = @TableName
AND IsDeleted = 0 --Not already removed
UNION
/*Inde xUsage History*/
SELECT dbname, SchemaName, TableName,
IndexName, IndexColumns, IncludeColumns, IndexFilter,
IndexType, IsPrimaryKey, IsUnique, IsDisabled, IsCompressed,
CompressionDescription, IndexSizeKB, LobDataSizeKB, [RowCount],
totalseeks, TotalScans, TotalLookups, TotalUpdates, IsDeleted,
InsertDate, SQLRestartDate, HistoryInsertDate, 
CleanupCommand, RollbackCommand
FROM DbMaintenance.audit.indexusagehistory
WHERE DBName = @DBName AND SchemaName = @SchemaName AND TableName = @TableName
AND IsDeleted = 0 --Not already removed
ORDER BY IndexColumns, IndexName, SQLRestartDate, HistoryInsertDate

/*Missing Indexes History*/
--SELECT *
--FROM DbMaintenance.dbo.IndexMissingIndexes
--WHERE DatabaseName = 'MessageTransport' AND tablename = '[MessageTransport].[dbo].[CampaignCallResult]'