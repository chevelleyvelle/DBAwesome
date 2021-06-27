USE [DbMaintenance]
GO

/****** Object:  Table [Audit].[TableScan]    Script Date: 6/16/2021 4:13:37 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Audit].[TableScan](
	[DBName] [nvarchar](128) NOT NULL,
	[SchemaName] [nvarchar](128) NOT NULL,
	[TableName] [nvarchar](128) NOT NULL,
	[LastUserScan] [datetime] NULL,
	[LastUserSeek] [datetime] NULL,
	[LastUserLookup] [datetime] NULL,
	[LastUserUpdate] [datetime] NULL,
	[IsNoStatDefaultDate] [bit] NOT NULL,
	[InsertDate] [datetime] NOT NULL,
	[ModifyDate] [datetime] NOT NULL,
 CONSTRAINT [PK_TableScan] PRIMARY KEY CLUSTERED 
(
	[DBName] ASC,
	[SchemaName] ASC,
	[TableName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [Audit].[TableScan] ADD  CONSTRAINT [DF_TableScan_IsNoStatDefaultDate]  DEFAULT ((0)) FOR [IsNoStatDefaultDate]
GO

ALTER TABLE [Audit].[TableScan] ADD  CONSTRAINT [DF_TableScan_InsertDate]  DEFAULT (getdate()) FOR [InsertDate]
GO

ALTER TABLE [Audit].[TableScan] ADD  CONSTRAINT [DF_TableScan_ModifyDate]  DEFAULT (getdate()) FOR [ModifyDate]
GO


