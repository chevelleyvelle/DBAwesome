USE [DbMaintenance]
GO

/****** Object:  Table [Audit].[IndexUsageHistory]    Script Date: 3/7/2024 10:03:35 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Audit].[IndexUsageHistory](
	[ID] [INT] IDENTITY(1,1) NOT NULL,
	[IndexUsageID] [INT] NOT NULL,
	[DBName] [NVARCHAR](128) NOT NULL,
	[ObjectID] [INT] NOT NULL,
	[SchemaName] [NVARCHAR](128) NULL,
	[TableName] [NVARCHAR](128) NULL,
	[IndexID] [INT] NOT NULL,
	[IndexName] [NVARCHAR](128) NOT NULL,
	[IndexColumns] [NVARCHAR](MAX) NULL,
	[IncludeColumns] [NVARCHAR](MAX) NULL,
	[IndexFilter] [NVARCHAR](MAX) NULL,
	[IndexType] [NVARCHAR](60) NULL,
	[IsPrimaryKey] [BIT] NULL,
	[IsClustered] [BIT] NULL,
	[IsUnique] [BIT] NULL,
	[IsUniqueConstraint] [BIT] NULL,
	[HasFilter] [BIT] NULL,
	[IsDisabled] [BIT] NULL,
	[IsCompressed] [BIT] NULL,
	[CompressionDescription] [NVARCHAR](60) NULL,
	[IndexSizeKB] [BIGINT] NULL,
	[LobDataSizeKB] [BIGINT] NULL,
	[RowCount] [BIGINT] NULL,
	[TotalSeeks] [BIGINT] NULL,
	[TotalScans] [BIGINT] NULL,
	[TotalLookups] [BIGINT] NULL,
	[TotalUpdates] [BIGINT] NULL,
	[LastUserSeek] [DATETIME] NULL,
	[LastUserScan] [DATETIME] NULL,
	[LastUserLookup] [DATETIME] NULL,
	[LastUserUpdate] [DATETIME] NULL,
	[ExcludeFromCleanup] [BIT] NOT NULL,
	[IsDeleted] [BIT] NOT NULL,
	[EmailSendDate] [DATETIME] NULL,
	[DisableIndexDate] [DATETIME] NULL,
	[DisableIndexCommand] [NVARCHAR](4000) NULL,
	[RebuildIndexCommand] [NVARCHAR](4000) NULL,
	[CleanupDate] [DATETIME] NULL,
	[CleanupCommand] [NVARCHAR](4000) NULL,
	[RollbackDate] [DATETIME] NULL,
	[RollbackCommand] [NVARCHAR](MAX) NULL,
	[InsertDate] [DATETIME] NOT NULL,
	[ModifyDate] [DATETIME] NOT NULL,
	[SQLRestartDate] [DATETIME] NULL,
	[HistoryInsertDate] [DATETIME] NOT NULL,
 CONSTRAINT [PK_IndexUsageHistory_ID] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [Audit].[IndexUsageHistory] ADD  CONSTRAINT [DF_IndexUsageHistory_HistoryInsertDate]  DEFAULT (GETDATE()) FOR [HistoryInsertDate]
GO

CREATE NONCLUSTERED INDEX [IX_IndexUsageHistory_HistoryInsertDate] ON [Audit].[IndexUsageHistory]
(
	[HistoryInsertDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
