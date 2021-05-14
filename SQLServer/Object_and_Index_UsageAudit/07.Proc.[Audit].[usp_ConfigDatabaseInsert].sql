USE [DB_Name]
GO


CREATE PROCEDURE [Audit].[usp_ConfigDatabaseInsert]
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 12/02/2019 
 Description: 
	 - Logs all databases on the Server/Instance
	 - Merge will not update the record if ExcludeFromCleanup = 0 so that we can manally 
		set Exclude and not have it overwritten.
	 - If server is part of an AG sets db's that are secondary role on the server as Exclude.
	 - This is used as part of a grooming/clean up process.  
		Used throughout the Grooming stored procs for which databases it should be grooming
	 - This is used as part of the emailing process that maps the instance/db to the SME to be emailed.

 exec Audit.usp_ConfigDatabaseInsert
 select * from Audit.ConfigDatabase
=========================================================================================== */
BEGIN

SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#DBTemp') IS NOT NULL
    DROP TABLE #DBTemp

CREATE TABLE #DBTemp (
	[InstanceName] [VARCHAR](100) NOT NULL,
	[ListenerName] [VARCHAR](100) NULL,
   	[DBName] [SYSNAME] NOT NULL,
	[IsActive] [BIT] NOT NULL,
	[ExcludeFromCleanup] [BIT] NOT NULL,
	[IsAGSecondary] [BIT] NOT NULL
	)
	INSERT INTO #DBTemp
	(
		InstanceName,
		ListenerName,
	    DBName,
	    IsActive,
	    ExcludeFromCleanup,
		IsAGSecondary
	)
	SELECT 
	   i.InstanceName,
	   i.ListenerName,
	   d.name AS DBName, 
	   1 AS IsActive,
	   CASE WHEN d.[name] IN ('master', 'model', 'msdb', 'tempdb', 'distribution', 'SSISDB') THEN 1
			WHEN d.[name] LIKE '%test%' THEN 1
			WHEN d.[name] LIKE '%ReportServer%' THEN 1
			ELSE 0 END AS ExcludeFromCleanup,
		CASE WHEN ISNULL(a.role_desc,'PRIMARY') ='SECONDARY' THEN 1 
			ELSE 0 END AS IsAGSecondary
    FROM sys.databases d
	LEFT JOIN sys.dm_hadr_availability_replica_states AS a ON d.replica_id = a.replica_id
	CROSS APPLY [Audit].tvf_ServerInstance() AS i
	WHERE 
		  d.is_in_standby = 0
		  AND d.state_desc = 'ONLINE'
	ORDER BY d.database_id;

	MERGE [Audit].ConfigDatabase AS MyTarget
	USING #DBTemp
	ON #DBTemp.DBName = MyTarget.DBName
	WHEN MATCHED AND MyTarget.ExcludeFromCleanup = 0 /* Hasn't been excluded */
		THEN
		UPDATE SET MyTarget.IsActive = #DBTemp.IsActive,
				   MyTarget.ExcludeFromCleanup = #DBTemp.ExcludeFromCleanup,
				   MyTarget.IsAGSecondary = #DBTemp.IsAGSecondary,
				   MyTarget.UpdateDate = GETDATE()
	WHEN NOT MATCHED THEN 
		INSERT (
				InstanceName,
				ListenerName,
				DBName,
				IsActive,
				ExcludeFromCleanup,
				IsAGSecondary,
				InsertDate,
				UpdateDate
				)
		VALUES (
				#DBTemp.InstanceName,
				#DBTemp.ListenerName,
				#DBTemp.DBName,
				#DBTemp.IsActive,
				#DBTemp.ExcludeFromCleanup,
				#DBTemp.IsAGSecondary,
				GETDATE(),
				GETDATE()
				)
	WHEN NOT MATCHED BY SOURCE AND MyTarget.IsActive = 1
		THEN
		UPDATE SET MyTarget.IsActive = 0,
				   MyTarget.UpdateDate = GETDATE();

END

GO


