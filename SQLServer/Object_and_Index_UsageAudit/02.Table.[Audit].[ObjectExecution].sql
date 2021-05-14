USE [DB_Name]
GO

CREATE TABLE [Audit].[ObjectExecution](
	[DBName] [sysname] NOT NULL,
	[SchemaName] [varchar](25) NOT NULL,
	[ObjectName] [varchar](250) NOT NULL,
	[ObjectType] [varchar](50) NULL,
	[LastExecutionDate] [datetime] NULL,
	[IsNoStatDefaultDate] [bit] NOT NULL,
 CONSTRAINT [PK_ObjectExection] PRIMARY KEY CLUSTERED 
(
	[DBName] ASC,
	[SchemaName] ASC,
	[ObjectName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [Audit].[ObjectExecution] ADD  CONSTRAINT [DF__ObjectExecution__IsNoStatDefaultDate]  DEFAULT ((0)) FOR [IsNoStatDefaultDate]
GO


