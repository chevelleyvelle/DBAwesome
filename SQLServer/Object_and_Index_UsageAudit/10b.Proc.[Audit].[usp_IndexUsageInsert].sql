USE [DbMaintenance]
GO

/****** Object:  StoredProcedure [Audit].[usp_IndexUsageInsert]    Script Date: 2/22/2024 1:03:57 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

---Need to add columns to the table then change the merge portion

CREATE OR ALTER PROCEDURE [Audit].[usp_IndexUsageInsert] @HistoryRetentionMonths INT = NULL, @TestMode BIT = NULL
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 09/01/2020 
 Modified: 03/05/2024
 Description: 
	 - Log all Heaps, Clustered and NonClustered indexes in non-excluded databases to a table in the DBA Team Database
	 - This version does not keep data persisted through startup, relies on history.
	 - This will be used in future analysis/automation of index cleanup for unused/duplicate/overlapping 
	   indexes.
	 - Only logs Heaps, Clustered and NonClustered indexes of [sys].[Indexes].[Type] IN (0,1,2)
		Excludes XML, Spatial, Clustered columnstore index, Nonclustered columnstore index, 
		and Nonclustered hash index.
		As of March 2024, started including Heaps Index type 0
	 - Calls [Audit].usp_IndexUsageHistoryInsert passing in @HistoryRetentionMonths.
		- Only keeps history retention in for @HistoryRetentionMonths as passed or default of 
			60 months if NULL passed.  This allows history of low use indexes to be viewed over 
			at least 5 years from time of logging start.
	 - DDL of the index does not include all settings for the index.  
		Does include Compression, Fill Factor, and data file.  Use with caution.  
		All other settings (lock, partitioning, etc not included here.)

	--March 2024 changes include compression, lob data of an index, heaps, Row count.
		Tweak of join to get index/log data size

	 -Parameters: @TestMode = 1 Print what would be logged without logging to table
							  NULLable.  If NULL Default 0
				  @HistoryRetentionMonths NULLable.  If NULL Default 18.
							  Used for history of [Audit].IndexUsageHistory
 Modification: 
 EXEC [Audit].[usp_IndexUsageInsert] @HistoryRetentionMonths= 60, @TestMode = 1
 EXEC [Audit].[usp_IndexUsageInsert] @HistoryRetentionMonths= 60, @TestMode = 0
 SELECT * FROM [Audit].[IndexUsage]
=========================================================================================== */
BEGIN 
	SET NOCOUNT ON;

/*Default TestMode to off when not passed and run code */
IF @TestMode IS NULL 
BEGIN
	SET @TestMode = 0 
END

IF @HistoryRetentionMonths IS NULL OR @HistoryRetentionMonths = 0
BEGIN
	SET @HistoryRetentionMonths = 60
END

/* Run History first */
IF @TestMode = 0
BEGIN
	EXECUTE [Audit].[usp_IndexUsageHistoryInsert] @RetentionMonths = @HistoryRetentionMonths;
END

/* Get last SQL Server Service Restart Date */
DECLARE @SQLRestart DATETIME
	SELECT @SQLRestart = sqlserver_start_time FROM sys.dm_os_sys_info

/* Proc Variables */
--/*Dyanmic SQL Variables*/--
DECLARE @IndexUsageQuery NVARCHAR(MAX)

DECLARE @IndexDDLQuery NVARCHAR(MAX)
DECLARE @IndexDDLParams NVARCHAR(MAX)
DECLARE @QueryParamObjectID NVARCHAR(1000)
DECLARE @QueryParamIndexID NVARCHAR(1000)

SET @IndexDDLParams = '@ObjectID INT, @IndexID INT'
SET @QueryParamObjectId = '@ObjectID'
SET @QueryParamIndexID = '@IndexID'

--/*Cursor Variables*/--
DECLARE @DBName VARCHAR(100),
		@ObjectID INT,
		@IndexID INT

/* Creat Temp Tables */
CREATE TABLE #Indexes 
	(	[ID] INT NOT NULL IDENTITY(1,1),
		[DBName] NVARCHAR(128) NOT NULL,
		[ObjectID] INT NOT NULL,
		[SchemaName] NVARCHAR(128) NULL,
		[TableName] NVARCHAR(128) NULL,
		[IndexID] INT NOT NULL,
		[IndexName] NVARCHAR(128) NOT NULL,
		[IndexColumns] NVARCHAR(MAX) NULL,
		[IncludeColumns] NVARCHAR(MAX) NULL,
		[IndexFilter] NVARCHAR(MAX) NULL,
		[IndexType] NVARCHAR(60) NULL,
		[IsPrimaryKey] BIT NULL,
		[IsClustered] BIT NULL,
		[IsUnique] BIT NULL,
		[IsUniqueConstraint] BIT NULL,
		[HasFilter] BIT NULL,
		[IsDisabled] BIT NULL,
		[IsCompressed] BIT NULL,
		[CompressionDescription] NVARCHAR(60) NULL,
		[IndexSizeKB] BIGINT NULL,
		[LobDataSizeKB] BIGINT NULL,
		[RowCount] BIGINT NULL,
		[Seeks] BIGINT NULL,
		[Scans] BIGINT NULL,
		[Lookups] BIGINT NULL,
		[Updates] BIGINT NULL,
		[LastUserSeek] DATETIME NULL,
		[LastUserScan] DATETIME NULL,
		[LastUserLookup] DATETIME NULL,
		[LastUserUpdate] DATETIME NULL,
		[ExcludeFromCleanup] BIT NULL,
		[IndexDisableDate] DATETIME NULL,
		[IndexDDL] NVARCHAR(MAX) NULL
	)

CREATE TABLE #index_column
(	[object_id] INT,
	[index_id] INT,
	[is_descending_key] BIT,
	[is_included_column] BIT,
	[name] NVARCHAR(128)
)

/* Get all Indexes in all databases */
DECLARE curDB CURSOR LOCAL STATIC FORWARD_ONLY FOR   
	SELECT DBName
	FROM [Audit].tvf_GetDatabaseList()
	ORDER BY DBName 
         
	 OPEN curDB    
	 FETCH NEXT FROM curDB INTO @DBName    
	 WHILE @@FETCH_STATUS = 0    
		BEGIN  

		SET @IndexUsageQuery = N'USE [' + @DBName +'];'
		SET @IndexUsageQuery = @IndexUsageQuery + CHAR(13) +
		N'DECLARE @database_id INT' + CHAR(13) +
		N'SELECT @database_id = database_id FROM sys.databases WHERE name = DB_NAME()' + CHAR(13) +
		N'SELECT 
			   DB_NAME() AS DBName, 
			   i.object_id AS ObjectID, 
			   s.[name] AS SchemaName,
			   o.[name] AS TableName,
			   i.index_id AS IndexID,
 			   ISNULL(i.[name],''HEAP'') AS IndexName,
			   icol.IndexColumns,
			   incol.IncludeColumns,
			   CASE WHEN i.has_filter = 1 AND i.filter_definition IS NOT NULL 
				  THEN i.filter_definition ELSE NULL END AS IndexFilter,
 			   i.type_desc AS IndexType,
			   i.is_primary_key AS IsPrimaryKey,
			   CASE WHEN i.Type = 1 THEN 1 ELSE 0 END AS IsClustered,
			   i.is_unique AS IsUnique,
			   i.is_unique_constraint AS IsUniqueConstraint,
 			   i.has_filter AS HasFilter,
 			   i.is_disabled AS IsDisabled,
			   CASE WHEN p.data_compression = 0 THEN 0 ELSE 1 END AS IsCompressed,
			   p.data_compression_desc AS CompressionDescription,
			   ----SUM(au.used_pages) * 8 AS IndexSizeKB,
			   SUM(au.total_pages) * 8 AS IndexSizeKB,
			   SUM(CASE WHEN au.type=2 THEN au.total_pages ELSE 0 END) * 8 AS LobDataSizeKb,
			   MAX(p.Rows) AS [RowCount],
 			   ISNULL(ixus.user_seeks, 0) AS Seeks,
 			   ISNULL(ixus.user_scans, 0) AS Scans,
 			   ISNULL(ixus.user_lookups, 0) AS Lookups,
 			   ISNULL(ixus.user_updates, 0) AS Updates,
 			   ixus.last_user_seek AS LastUserSeek,
 			   ixus.last_user_scan AS LastUserScan,
 			   ixus.last_user_lookup AS LastUserLookup,
 			   ixus.last_user_update AS LastUserUpdate
		 FROM sys.objects o
		 INNER JOIN sys.schemas s 
			ON o.schema_id = s.schema_id
		 INNER JOIN sys.indexes i 
			ON o.object_id = i.object_id
		 LEFT JOIN sys.dm_db_index_usage_stats ixus 
			ON  i.index_id = ixus.index_id  
				AND i.object_id = ixus.object_id 
				AND ixus.database_id = @database_id
		 LEFT JOIN sys.partitions AS p 
			ON i.object_id = p.object_id 
				AND i.index_id = p.index_id
		 LEFT JOIN sys.allocation_units AS au 
			----ON p.partition_id = au.container_id
			ON p.hobt_id = au.container_id
		 CROSS APPLY 
		(
			SELECT STUFF
			(
				(
					SELECT '' ['' + col.name + '']''
					FROM sys.index_columns ixcls
					INNER JOIN sys.columns col 
						ON ixcls.object_id = col.object_id 
							AND ixcls.column_id = col.column_id
					WHERE i.object_id = ixcls.object_id 
						AND i.index_id = ixcls.index_id
						AND ixcls.is_included_column = 0
					FOR XML PATH('''')
				)
				,1
				,1
				,''''
			) 
		) icol ([IndexColumns])
		CROSS APPLY 
		(
			SELECT STUFF
			(
				(
					SELECT '' ['' + col.name + '']''
					FROM sys.index_columns ixcls
					INNER JOIN sys.columns col 
						ON ixcls.object_id = col.object_id 
							AND ixcls.column_id = col.column_id
					WHERE i.object_id = ixcls.object_id 
						AND i.index_id = ixcls.index_id
						AND ixcls.is_included_column = 1
					FOR XML PATH('''')
				)
				,1
				,1
				,''''
			) 
		) incol ([IncludeColumns])
		 WHERE o.type = ''U'' 
			AND i.type IN (0,1,2) 
			AND o.name <> ''sysdiagrams'' 
			AND o.is_ms_shipped = 0
		 GROUP BY i.object_id, s.[name], o.[name], i.index_id, i.[name], icol.IndexColumns, incol.IncludeColumns, 
		 CASE WHEN i.has_filter = 1 AND i.filter_definition IS NOT NULL THEN i.filter_definition ELSE NULL END, i.type_desc, i.is_primary_key, 
		 CASE WHEN i.type = 1 THEN 1 ELSE 0 END, i.is_unique, i.is_unique_constraint, ixus.user_seeks, ixus.user_scans, ixus.user_lookups,   
		 i.has_filter, i.is_disabled, ixus.user_updates, ixus.last_user_seek, ixus.last_user_scan, ixus.last_user_lookup, ixus.last_user_update,
		 CASE WHEN p.data_compression = 0 THEN 0 ELSE 1 END, p.data_compression_desc'
		 		
		BEGIN TRY  

			INSERT INTO #Indexes
			(DBName, ObjectID, SchemaName, TableName, IndexID, IndexName, IndexColumns, IncludeColumns, IndexFilter, 
			 IndexType, IsPrimaryKey, IsClustered, IsUnique, IsUniqueConstraint, HasFilter, IsDisabled, IsCompressed,
			 CompressionDescription, IndexSizeKB, LobDataSizeKB, [RowCount], Seeks, Scans, Lookups, Updates, 
			 LastUserSeek, LastUserScan, LastUserLookup, LastUserUpdate)
		    EXECUTE sp_executesql @IndexUsageQuery

		 END TRY  
		 BEGIN CATCH

			 IF @@TRANCOUNT > 0
				ROLLBACK TRAN

			 PRINT 'ERROR on curDB (Get index usage) for database '+ @DBName;

		 END CATCH  
	 FETCH NEXT FROM curDB INTO @DBName    
		END   
        
	 CLOSE curDB    
	 DEALLOCATE curDB  

/* Get all index column info and DDL Create statement */
   	DECLARE cur_IndexDDL CURSOR LOCAL FAST_FORWARD FOR
		SELECT DBName, ObjectID, IndexID
		FROM #Indexes
		ORDER BY DBName, ObjectID

	OPEN cur_IndexDDL;
	FETCH cur_IndexDDL
	INTO @DBName, @ObjectID, @IndexID

	WHILE @@FETCH_STATUS = 0
	BEGIN 
	BEGIN TRY  

	TRUNCATE TABLE #index_column

		SET @IndexDDLQuery = N'USE [' + @DBName + N']'
		SET @IndexDDLQuery = @IndexDDLQuery + CHAR(13) +
			N'DECLARE @DDL NVARCHAR(MAX) = N''''' + CHAR(13) +
			N'SELECT 
				 ic.object_id,
				 ic.index_id,
				 ic.is_descending_key,
				 ic.is_included_column,
				 c.[name]
			INTO #index_column
			FROM sys.index_columns ic WITH (NOWAIT)
			JOIN sys.columns c WITH (NOWAIT) 
				ON ic.object_id = c.object_id 
					AND ic.column_id = c.column_id
			WHERE ic.object_id = ' + @QueryParamObjectId +  CHAR(13) + ' AND ic.index_id = ' + @QueryParamIndexID + CHAR(13) +
		'SELECT @DDL = 
		------------------- INDEXES ----------------------------------------------------------------------------------------------------------
			CAST(
				ISNULL(((SELECT
					 NCHAR(13) + N''CREATE'' + CASE WHEN i.is_unique = 1 THEN N'' UNIQUE '' ELSE N'' '' END 
							+ i.type_desc + N'' INDEX '' + QUOTENAME(i.name) + N'' ON '' + + QUOTENAME(s.name) + N''.'' + QUOTENAME(o.name) + + N'' ('' +
							STUFF((
							SELECT N'', '' + QUOTENAME(c.name) + N'''' + CASE WHEN c.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
							FROM #index_column c
							WHERE c.is_included_column = 0
								AND c.index_id = i.index_id
							FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') + N'')''  
							+ ISNULL(NCHAR(13) + N''INCLUDE ('' + 
								STUFF((
								SELECT N'', '' + QUOTENAME(c.name) + N''''
								FROM #index_column c
								WHERE c.is_included_column = 1
									AND c.index_id = i.index_id
								FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') + N'')'', N'''')  + NCHAR(13)
								+ CASE WHEN i.filter_definition IS NOT NULL THEN N'' WHERE '' + i.filter_definition ELSE N'' '' END 
								+ '' WITH (ONLINE = ON''+  CASE WHEN i.fill_factor <> 0 THEN N'', FILLFACTOR = '' + CAST(i.fill_factor AS VARCHAR(10)) + N'' ''  ELSE N'' '' END +
								+  CASE WHEN  p.data_compression <> 0 THEN N'', DATA_COMPRESSION = '' + p.data_compression_desc + N'')''  ELSE N'')'' END +'' ON '' + QUOTENAME(ds.name)
					FROM sys.indexes i WITH (NOWAIT)
					JOIN sys.objects o 
						ON i.object_id = o.object_id
					JOIN sys.schemas s
						ON o.schema_id = s.schema_id
					JOIN sys.data_spaces ds 
						ON i.data_space_id = ds.data_space_id
					 LEFT JOIN sys.partitions AS p 
						ON i.object_id = p.object_id 
						AND i.index_id = p.index_id
					WHERE i.object_id = ' + @QueryParamObjectId + ' AND i.index_id = ' + @QueryParamIndexID + 
						' AND i.type IN (1,2) --Only Clustered and NonClustered Indexes
					FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)'')
				), N'''')
			AS NVARCHAR(MAX))

			/* Update #ObjectDDL */
			UPDATE i
			SET  IndexDDL = @DDL,
				 ExcludeFromCleanup = CASE WHEN i.IsPrimaryKey = 1 OR i.IsClustered = 1 OR i.IsUnique = 1 OR i.IsUniqueConstraint = 1
											 THEN 1 ELSE 0 END
			FROM #Indexes i
			WHERE i.DBName = DB_NAME() 
				AND ObjectID = ' + @QueryParamObjectId + ' AND IndexID = ' + @QueryParamIndexID + ';'
		

		EXECUTE sp_executesql @IndexDDLQuery, @IndexDDLParams, @ObjectId = @ObjectID, @IndexID = @IndexID

	 END TRY
	 BEGIN CATCH

		IF @@TRANCOUNT > 0
			ROLLBACK TRAN

		/* This will cause the merge below to mark index as IsDeleted=1 since it is not in the table 
			This is needed so that if automating processes in the future to clean indexes it should look at ExcludeFromCleanUp and IsDeleted to ignore those.
			Next time it runs if it logs the index without failure it will mark the index IsDeleted back to 0 */
		DELETE FROM #Indexes WHERE DBName = @DBName AND ObjectID = @ObjectID AND IndexID = @IndexID
		
		PRINT 'ERROR on cur_IndexDDL (Get index DDLs) for database '+@DBName + ' ObjectID ' +CAST(@ObjectID AS VARCHAR(10)) + ' IndexID ' +CAST(@IndexID AS VARCHAR(10));  
			 
	 END CATCH  

	FETCH NEXT FROM cur_IndexDDL
    INTO @DBName, @ObjectID, @IndexID
	END
	CLOSE cur_IndexDDL;
	DEALLOCATE cur_IndexDDL;

IF @TestMode = 0
BEGIN
	MERGE [Audit].IndexUsage AS MyTarget
	USING #Indexes
	ON #Indexes.DBName = MyTarget.DBName
		AND #Indexes.ObjectID = MyTarget.ObjectID 
		AND #Indexes.IndexID = MyTarget.IndexID
		AND #Indexes.IndexName = MyTarget.IndexName
	WHEN MATCHED AND MyTarget.CleanupDate IS NULL --AND MyTarget.ExcludeFromCleanup=0  /* Hasn't been renamed already and not already excluded */
		THEN
		UPDATE SET	
				IndexColumns = #Indexes.IndexColumns,
				IncludeColumns = #Indexes.IncludeColumns,
				IndexFilter = #Indexes.IndexFilter,
				IndexType = #Indexes.IndexType,
				IsPrimaryKey = #Indexes.IsPrimaryKey,
				IsClustered = #Indexes.IsClustered,
				IsUnique = #Indexes.IsUnique,
				IsUniqueConstraint = #Indexes.IsUniqueConstraint,
				HasFilter = #Indexes.HasFilter,
				IsDisabled = #Indexes.IsDisabled,
				IsCompressed = #Indexes.IsCompressed,
				CompressionDescription = #Indexes.CompressionDescription,
				IndexSizeKB = ISNULL(#Indexes.IndexSizeKB, MyTarget.IndexSizeKB),
				LobDataSizeKB = ISNULL(#Indexes.LobDataSizeKB, MyTarget.LobDataSizeKB),
				[RowCount] = #Indexes.[RowCount],
				TotalSeeks = #Indexes.Seeks,
				TotalScans = #Indexes.Scans,
				TotalLookups = #Indexes.[Lookups],
				TotalUpdates = #Indexes.Updates,					
				LastUserSeek = #Indexes.LastUserSeek,	
				LastUserScan = #Indexes.LastUserScan,
				LastUserLookup = #Indexes.LastUserLookup,
				LastUserUpdate = #Indexes.LastUserUpdate,
				ExcludeFromCleanup = CASE WHEN MyTarget.ExcludeFromCleanup = 1 THEN  1 ELSE COALESCE(#Indexes.ExcludeFromCleanup,0) END,
				IsDeleted = 0,
				DisableIndexDate = CASE WHEN #Indexes.IsDisabled = 1 THEN ISNULL(MyTarget.DisableIndexDate, GETDATE()) ELSE NULL END,
				DisableIndexCommand = 'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + ''') '+
										' BEGIN ALTER INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' DISABLE END;',
				RebuildIndexCommand = 'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + '''AND is_disabled = 1) '+
										' BEGIN ALTER INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' REBUILD WITH (ONLINE=ON) END;',
				CleanupCommand = 'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + ''') '+
									' BEGIN DROP INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' END;',
				RollbackCommand = 'IF NOT EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + ''') '+ ' BEGIN  ' + #Indexes.IndexDDL + ' END;',
				ModifyDate = GETDATE(),
				SQLRestartDate = @SQLRestart
	WHEN NOT MATCHED THEN
	INSERT (
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
		IsCompressed,
		CompressionDescription,
		IndexSizeKB,
		LobDataSizeKB,
		[RowCount],
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
		SQLRestartDate
		)
		VALUES (
			#Indexes.DBName,
			#Indexes.ObjectID,
			#Indexes.SchemaName,
			#Indexes.TableName,
			#Indexes.IndexID,
			#Indexes.IndexName,
			#Indexes.IndexColumns,
			#Indexes.IncludeColumns,
			#Indexes.IndexFilter,
			#Indexes.IndexType,
			#Indexes.IsPrimaryKey,
			#Indexes.IsClustered,
			#Indexes.IsUnique,
			#Indexes.IsUniqueConstraint,
			#Indexes.HasFilter,
			#Indexes.IsDisabled,
			#Indexes.IsCompressed,
			#Indexes.CompressionDescription,
			#Indexes.IndexSizeKB,
			#Indexes.LobDataSizeKB,
			#Indexes.[RowCount],
			#Indexes.Seeks,
			#Indexes.Scans,
			#Indexes.Lookups,
			#Indexes.Updates,
			#Indexes.LastUserSeek,
			#Indexes.LastUserScan,
			#Indexes.LastUserLookup,
			#Indexes.LastUserUpdate,
			#Indexes.ExcludeFromCleanup,
			0,
			NULL,
			CASE WHEN #Indexes.IsDisabled = 1 THEN GETDATE() ELSE NULL END,
			'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.[IndexName] + ''') '+
										' BEGIN ALTER INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' DISABLE END;',
			'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + '''AND [is_disabled] = 1) '+
										' BEGIN ALTER INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' REBUILD WITH (ONLINE=ON) END;',
			NULL,
			'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + ''') '+
									' BEGIN DROP INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' END;',
			NULL,
			'IF NOT EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + ''') '+ ' BEGIN  ' + #Indexes.IndexDDL + ' END;',
			GETDATE(),
			GETDATE(),
			@SQLRestart
			)
	WHEN NOT MATCHED BY SOURCE AND MyTarget.CleanupDate IS NULL AND MyTarget.IsDeleted = 0 THEN
		UPDATE SET MyTarget.IsDeleted = 1, MyTarget.ModifyDate = GETDATE();	
	
	END

IF @TestMode = 1
	BEGIN

	SELECT 
		#Indexes.DBName,
		#Indexes.ObjectID,
		#Indexes.SchemaName,
		#Indexes.TableName,
		#Indexes.IndexID,
		#Indexes.IndexName,
		#Indexes.IndexColumns,
		#Indexes.IncludeColumns,
		#Indexes.IndexFilter,
		#Indexes.IndexType,
		#Indexes.IsPrimaryKey,
		#Indexes.IsClustered,
		#Indexes.IsUnique,
		#Indexes.IsUniqueConstraint,
		#Indexes.HasFilter,
		#Indexes.IsDisabled,
		#Indexes.IsCompressed,
		#Indexes.CompressionDescription,
		#Indexes.IndexSizeKB,
		#Indexes.LobDataSizeKB,
		#Indexes.[RowCount],
		#Indexes.Seeks AS TotalSeeks,
		#Indexes.Scans AS TotalScans,
		#Indexes.Lookups AS TotalLookups,
		#Indexes.Updates AS TotalUpdates,					
		#Indexes.LastUserSeek AS LastUserSeek,	
		#Indexes.LastUserScan AS LastUserScan,
		#Indexes.LastUserLookup AS LastUserLookup,
		#Indexes.LastUserUpdate AS LastUserUpdate,
		CASE WHEN MyTarget.ExcludeFromCleanup = 1 THEN 1 ELSE COALESCE(#Indexes.ExcludeFromCleanup, 0) END AS ExcludeFromCleanup,
		CASE WHEN MyTarget.ObjectID IS NOT NULL THEN MyTarget.EmailSendDate ELSE NULL END AS EmailSendDate,
		CASE WHEN MyTarget.ObjectID IS NOT NULL AND #Indexes.IsDisabled = 1 THEN ISNULL(MyTarget.DisableIndexDate, GETDATE()) 
			 WHEN MyTarget.ObjectID IS NULL AND #Indexes.IsDisabled = 1 THEN ISNULL(MyTarget.DisableIndexDate, GETDATE()) 
			 ELSE NULL END AS DisableIndexDate,
		'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + ''') '+
										' BEGIN ALTER INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' DISABLE END;' AS DisableIndexCommand,
		'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + '''AND [is_disabled] = 1) '+
										' BEGIN ALTER INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' REBUILD WITH (ONLINE=ON) END;' AS RebuildIndexCommand,
		CASE WHEN MyTarget.[ObjectID] IS NOT NULL THEN MyTarget.CleanupDate ELSE NULL END AS CleanupDate,
		'IF EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + ''') '+
									' BEGIN DROP INDEX ' + QUOTENAME(#Indexes.IndexName) + ' ON ' + QUOTENAME(#Indexes.SchemaName) + '.' + QUOTENAME(#Indexes.TableName) + ' END;' AS CleanupCommand,
		CASE WHEN MyTarget.ObjectID IS NOT NULL THEN MyTarget.RollbackDate ELSE NULL END AS RollbackDate,
		'IF NOT EXISTS (SELECT 1 FROM [sys].[indexes] WHERE [name] = '+'''' + #Indexes.IndexName + ''') '+ ' BEGIN  ' + #Indexes.IndexDDL + ' END;' AS RollbackCommand,
		@SQLRestart AS SQLRestartDate
	FROM #Indexes
	LEFT JOIN [Audit].IndexUsage AS MyTarget 
		ON #Indexes.DBName = MyTarget.DBName 
			AND #Indexes.ObjectID = MyTarget.ObjectID
			AND #Indexes.IndexID = MyTarget.IndexID
			AND #Indexes.IndexName = MyTarget.IndexName
	--WHERE MyTarget.ObjectID IS NOT NULL
	ORDER BY #Indexes.DBName, #Indexes.SchemaName, #Indexes.TableName
	
	END
END


GO
