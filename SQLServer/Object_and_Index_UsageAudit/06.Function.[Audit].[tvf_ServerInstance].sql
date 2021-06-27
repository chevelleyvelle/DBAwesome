USE [DbMaintenance]
GO

/****** Object:  UserDefinedFunction [Audit].[tvf_ServerInstance]    Script Date: 6/16/2021 4:16:21 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   FUNCTION [Audit].[tvf_ServerInstance] ()
RETURNS @Instance TABLE(InstanceName NVARCHAR(256), InstanceIP VARCHAR(48), InstancePort INT, ListenerName NVARCHAR(63), ListenerPort INT, IsReadableSecondary BIT)
AS 
BEGIN
	/*----------------------------------------------------------------------------
		Get Listener if part of AG
		Get Primary first if no primary, get the listener for sthe secondary
	----------------------------------------------------------------------------*/
	DECLARE @ListenerName NVARCHAR(63)
	DECLARE @ListenerPort INT
	DECLARE @IsReadableSecondary BIT
	DECLARE @InstanceName NVARCHAR(256)
	DECLARE @InstancePort INT
	DECLARE @InstanceIP VARCHAR(48)

	SET @InstanceName = @@SERVERNAME

	SELECT 
		@ListenerName = agl.dns_name, 
		@ListenerPort = agl.[port], 
		@IsReadableSecondary = CASE WHEN agr.secondary_role_allow_connections IN (1,2) THEN 1 ELSE 0 END
	FROM sys.availability_group_listeners agl
	JOIN sys.availability_replicas agr ON agr.group_id = agl.group_id
	JOIN sys.dm_hadr_availability_replica_states ars ON agr.replica_id = ars.replica_id
	WHERE ars.role_desc = 'PRIMARY'

	IF @ListenerName IS NULL AND @ListenerPort IS NULL
	BEGIN 
		SELECT 
			@ListenerName =agl.dns_name, 
			@ListenerPort = agl.[port],
			@IsReadableSecondary = CASE WHEN agr.secondary_role_allow_connections IN (1,2) THEN 1 ELSE 0 END
		FROM sys.availability_group_listeners agl
		JOIN sys.availability_replicas agr ON agr.group_id = agl.group_id
		JOIN sys.dm_hadr_availability_replica_states ars ON agr.replica_id = ars.replica_id
		WHERE ars.role_desc = 'SECONDARY'
	END

	SELECT 
		@InstanceIP = local_net_address,
		@InstancePort = local_tcp_port	
	FROM sys.dm_exec_connections 
	WHERE session_id = @@spid


	INSERT INTO @Instance
	(
		InstanceName,
		InstanceIP,
		InstancePort,
		ListenerName,
		ListenerPort,
		IsReadableSecondary
	)
	SELECT 
		@InstanceName,
		@InstanceIP,
		@InstancePort,
		@ListenerName,
		@ListenerPort,
		@IsReadableSecondary


	RETURN
END

GO


