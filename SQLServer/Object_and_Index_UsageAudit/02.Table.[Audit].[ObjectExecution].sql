USE [DbMaintenance]
GO

/****** Object:  Table [Audit].[ObjectExecution]    Script Date: 6/16/2021 4:14:05 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Audit].[ObjectExecution](
	[DBName] [nvarchar](128) NOT NULL,
	[SchemaName] [nvarchar](128) NOT NULL,
	[ObjectName] [nvarchar](128) NOT NULL,
	[ObjectType] [nvarchar](60) NULL,
	[LastExecutionDate] [datetime] NULL,
	[IsNoStatDefaultDate] [bit] NOT NULL,
	[InsertDate] [datetime] NOT NULL,
	[ModifyDate] [datetime] NOT NULL,
 CONSTRAINT [PK_ObjectExection] PRIMARY KEY CLUSTERED 
(
	[DBName] ASC,
	[SchemaName] ASC,
	[ObjectName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [Audit].[ObjectExecution] ADD  CONSTRAINT [DF_ObjectExecution_IsNoStatDefaultDate]  DEFAULT ((0)) FOR [IsNoStatDefaultDate]
GO

ALTER TABLE [Audit].[ObjectExecution] ADD  CONSTRAINT [DF_ObjectExecution_InsertDate]  DEFAULT (getdate()) FOR [InsertDate]
GO

ALTER TABLE [Audit].[ObjectExecution] ADD  CONSTRAINT [DF_ObjectExecution_ModifyDate]  DEFAULT (getdate()) FOR [ModifyDate]
GO


