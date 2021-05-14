USE [DB_Name]
GO

CREATE TABLE [Audit].[ConfigDatabase](
	[ConfigDatabaseID] [int] IDENTITY(1,1) NOT NULL,
	[InstanceName] [varchar](100) NOT NULL,
	[ListenerName] [varchar](100) NULL,
	[DBName] [sysname] NOT NULL,
	[IsActive] [bit] NOT NULL,
	[ExcludeFromCleanup] [bit] NOT NULL,
	[IsAGSecondary] [bit] NOT NULL,
	[InsertDate] [datetime] NOT NULL,
	[UpdateDate] [datetime] NOT NULL,
 CONSTRAINT [PK_ConfigDatabase_ConfigDatabaseID] PRIMARY KEY CLUSTERED 
(
	[ConfigDatabaseID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [Audit].[ConfigDatabase] ADD  CONSTRAINT [DF_ConfigDatabase_IsActive]  DEFAULT ((1)) FOR [IsActive]
GO

ALTER TABLE [Audit].[ConfigDatabase] ADD  CONSTRAINT [DF_ConfigDatabase_ExcludeFromCleanup]  DEFAULT ((0)) FOR [ExcludeFromCleanup]
GO

ALTER TABLE [Audit].[ConfigDatabase] ADD  CONSTRAINT [DF_ConfigDatabase_IsAGSecondary]  DEFAULT ((0)) FOR [IsAGSecondary]
GO

ALTER TABLE [Audit].[ConfigDatabase] ADD  CONSTRAINT [DF_ConfigDatabase_InsertDate]  DEFAULT (getdate()) FOR [InsertDate]
GO

ALTER TABLE [Audit].[ConfigDatabase] ADD  CONSTRAINT [DF_ConfigDatabase_UpdateDate]  DEFAULT (getdate()) FOR [UpdateDate]
GO


