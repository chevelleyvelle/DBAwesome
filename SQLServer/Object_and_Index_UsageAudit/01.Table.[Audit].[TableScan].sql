USE [DB_Name]
GO

CREATE TABLE [Audit].[TableScan](
	[DBName] [sysname] NOT NULL,
	[SchemaName] [varchar](25) NOT NULL,
	[TableName] [varchar](250) NOT NULL,
	[LastUserScan] [datetime] NULL,
	[LastUserSeek] [datetime] NULL,
	[LastUserLookup] [datetime] NULL,
	[IsNoStatDefaultDate] [bit] NOT NULL,
	[LastUserUpdate] [datetime] NULL,
 CONSTRAINT [PK_TableScan] PRIMARY KEY CLUSTERED 
(
	[DBName] ASC,
	[SchemaName] ASC,
	[TableName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [Audit].[TableScan] ADD  CONSTRAINT [DF__TableScan__IsNoStatDefaultDate]  DEFAULT ((0)) FOR [IsNoStatDefaultDate]
GO


