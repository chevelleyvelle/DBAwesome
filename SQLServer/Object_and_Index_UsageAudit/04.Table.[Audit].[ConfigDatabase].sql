USE [DbMaintenance]
GO

/****** Object:  Table [Audit].[ConfigDatabase]    Script Date: 6/16/2021 4:14:49 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Audit].[ConfigDatabase](
	[ConfigDatabaseID] [int] IDENTITY(1,1) NOT NULL,
	[InstanceName] [nvarchar](256) NOT NULL,
	[InstanceIP] [varchar](48) NULL,
	[InstancePort] [int] NULL,
	[ListenerName] [nvarchar](63) NULL,
	[ListenerPort] [int] NULL,
	[DBName] [nvarchar](128) NOT NULL,
	[IsActive] [bit] NOT NULL,
	[ExcludeFromCleanup] [bit] NOT NULL,
	[IsAGSecondary] [bit] NOT NULL,
	[IsReadableSecondary] [bit] NOT NULL,
	[InsertDate] [datetime] NOT NULL,
	[ModifyDate] [datetime] NOT NULL,
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

ALTER TABLE [Audit].[ConfigDatabase] ADD  CONSTRAINT [DF_ConfigDatabase_IsReadableSecondary]  DEFAULT ((0)) FOR [IsReadableSecondary]
GO

ALTER TABLE [Audit].[ConfigDatabase] ADD  CONSTRAINT [DF_ConfigDatabase_InsertDate]  DEFAULT (getdate()) FOR [InsertDate]
GO

ALTER TABLE [Audit].[ConfigDatabase] ADD  CONSTRAINT [DF_ConfigDatabase_ModifyDate]  DEFAULT (getdate()) FOR [ModifyDate]
GO


