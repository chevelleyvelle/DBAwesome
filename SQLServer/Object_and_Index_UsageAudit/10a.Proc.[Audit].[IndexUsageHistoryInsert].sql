USE [DbMaintenance]
GO

/****** Object:  StoredProcedure [Audit].[usp_IndexUsageHistoryInsert]    Script Date: 6/26/2021 5:25:00 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE   PROCEDURE [Audit].[usp_IndexUsageHistoryInsert] @RetentionMonths INT = NULL
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 06/26/021 
 Description: 
	 - If Sqlserver_start_time > last logged entry in [Audit].[IndexUsage] then insert all 
	   [Audit].[IndexUsage] into [Audit].[IndexUsageHistory] 
	 - This will be used in future analysis/automation of index cleanup for unused/duplicate/overlapping 
	   indexes.
	 - Only stores Clustered and NonClustered indexes of [sys].[Indexes].[Type] IN (1,2)
		Excludes XML, Spatial, Clustered columnstore index, Nonclustered columnstore index, 
		and Nonclustered hash index.
	 - Only keeps history retention for @RetentionMonths as passed or default of 18 months if NULL passed
		This allows history of low use indexes to be viewed over at least a year from time
		of logging start
 Modification: 
 EXEC [Audit].[usp_IndexUsageHistoryInsert] @RetentionMonths=18
 SELECT * FROM [Audit].[IndexUsageHistory]
=========================================================================================== */
BEGIN 
	SET NOCOUNT ON;

/* If @RetentionMonths IS NULL Defaut 18 */
IF @RetentionMonths IS NULL
BEGIN
	SET @RetentionMonths = 18
END

DECLARE @RetentionDate DATETIME = DATEADD(MONTH,-@RetentionMonths,GETDATE())

/* Get last SQL Server Service Restart Date */
DECLARE @SQLRestart DATETIME
	SELECT @SQLRestart = sqlserver_start_time FROM sys.dm_os_sys_info

/* Get last modified date of [Audit].[IndexUsage] */
DECLARE @LastIndexLog DATETIME
	SELECT @LastIndexLog = MAX(ModifyDate)
	FROM [Audit].IndexUsage

IF @SQLRestart > @LastIndexLog
BEGIN

	INSERT INTO [Audit].IndexUsageHistory
	(	IndexUsageID, DBName, ObjectID, SchemaName, TableName, IndexID, IndexName,
		IndexColumns, IncludeColumns, IndexFilter, IndexType, IsPrimaryKey, IsClustered,
		IsUnique, IsUniqueConstraint, HasFilter, IsDisabled, IndexSizeKB, TotalSeeks,
		TotalScans, TotalLookups, TotalUpdates, LastUserSeek, LastUserScan, LastUserLookup,
		LastUserUpdate, ExcludeFromCleanup, IsDeleted, EmailSendDate, DisableIndexDate,
		DisableIndexCommand, RebuildIndexCommand, CleanupDate, CleanupCommand, RollbackDate,
		RollbackCommand, InsertDate, ModifyDate, SQLRestartDate, HistoryInsertDate
	)
	SELECT 
		ID,
		DBName,
		ObjectID,
		SchemaName,
		TableName,
		IndexID,
		IndexName,
		IndexColumns,
		IncludeColumns,
		IndexFilter,
		IndexType,
		IsPrimaryKey,
		IsClustered,
		IsUnique,
		IsUniqueConstraint,
		HasFilter,
		IsDisabled,
		IndexSizeKB,
		TotalSeeks,
		TotalScans,
		TotalLookups,
		TotalUpdates,
		LastUserSeek,
		LastUserScan,
		LastUserLookup,
		LastUserUpdate,
		ExcludeFromCleanup,
		IsDeleted,
		EmailSendDate,
		DisableIndexDate,
		DisableIndexCommand,
		RebuildIndexCommand,
		CleanupDate,
		CleanupCommand,
		RollbackDate,
		RollbackCommand,
		InsertDate,
		ModifyDate,
		SQLRestartDate,
		GETDATE()
	FROM [Audit].IndexUsage

END

/* Delete history over retention */
	DELETE FROM [Audit].IndexUsageHistory WHERE HistoryInsertDate <= @RetentionDate;

RETURN;

END

GO


