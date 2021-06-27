USE [DbMaintenance]
GO

/****** Object:  Table [Audit].[IndexUsage]    Script Date: 6/16/2021 4:14:29 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Audit].[IndexUsage](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DBName] [nvarchar](128) NOT NULL,
	[ObjectID] [int] NOT NULL,
	[SchemaName] [nvarchar](128) NULL,
	[TableName] [nvarchar](128) NULL,
	[IndexID] [int] NOT NULL,
	[IndexName] [nvarchar](128) NOT NULL,
	[IndexColumns] [nvarchar](max) NULL,
	[IncludeColumns] [nvarchar](max) NULL,
	[IndexFilter] [nvarchar](max) NULL,
	[IndexType] [nvarchar](60) NULL,
	[IsPrimaryKey] [bit] NULL,
	[IsClustered] [bit] NULL,
	[IsUnique] [bit] NULL,
	[IsUniqueConstraint] [bit] NULL,
	[HasFilter] [bit] NULL,
	[IsDisabled] [bit] NULL,
	[IndexSizeKB] [bigint] NULL,
	[TotalSeeks] [bigint] NULL,
	[TotalScans] [bigint] NULL,
	[TotalLookups] [bigint] NULL,
	[TotalUpdates] [bigint] NULL,
	[LastUserSeek] [datetime] NULL,
	[LastUserScan] [datetime] NULL,
	[LastUserLookup] [datetime] NULL,
	[LastUserUpdate] [datetime] NULL,
	[ExcludeFromCleanup] [bit] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[EmailSendDate] [datetime] NULL,
	[DisableIndexDate] [datetime] NULL,
	[DisableIndexCommand] [nvarchar](4000) NULL,
	[RebuildIndexCommand] [nvarchar](4000) NULL,
	[CleanupDate] [datetime] NULL,
	[CleanupCommand] [nvarchar](4000) NULL,
	[RollbackDate] [datetime] NULL,
	[RollbackCommand] [nvarchar](max) NULL,
	[InsertDate] [datetime] NOT NULL,
	[ModifyDate] [datetime] NOT NULL,
	[SQLRestartDate] [datetime] NULL,
 CONSTRAINT [PK_IndexUsage_ID] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [Audit].[IndexUsage] ADD  CONSTRAINT [DF_IndexUsage_ExcludeFromCleanup]  DEFAULT ((0)) FOR [ExcludeFromCleanup]
GO

ALTER TABLE [Audit].[IndexUsage] ADD  CONSTRAINT [DF_IndexUsage_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO

ALTER TABLE [Audit].[IndexUsage] ADD  CONSTRAINT [DF_IndexUsage_InsertDate]  DEFAULT (getdate()) FOR [InsertDate]
GO

ALTER TABLE [Audit].[IndexUsage] ADD  CONSTRAINT [DF_IndexUsage_ModifyDate]  DEFAULT (getdate()) FOR [ModifyDate]
GO


