USE [DB_Name]
GO

CREATE FUNCTION [Audit].[tvf_ServerInstance] ()
RETURNS @Instance TABLE(InstanceName VARCHAR(100), ListenerName VARCHAR(100))
AS 
BEGIN
	/*----------------------------------------------------------------------------
		Get Listener if part of AG
		Get Primary first if no primary, get the listener for sthe secondary
	----------------------------------------------------------------------------*/
	DECLARE @ListenerName VARCHAR(156)
	DECLARE @ListenerPort INT

	SELECT @ListenerName =agl.dns_name, @ListenerPort = agl.port
	FROM sys.availability_group_listeners agl
	JOIN sys.availability_replicas agr ON agr.group_id = agl.group_id
	JOIN sys.dm_hadr_availability_replica_states ars ON agr.replica_id = ars.replica_id
	WHERE ars.role_desc = 'PRIMARY'

	IF @ListenerName IS NULL AND @ListenerPort IS NULL
	BEGIN 
		SELECT @ListenerName =agl.dns_name, @ListenerPort = agl.port
		FROM sys.availability_group_listeners agl
		JOIN sys.availability_replicas agr ON agr.group_id = agl.group_id
		JOIN sys.dm_hadr_availability_replica_states ars ON agr.replica_id = ars.replica_id
		WHERE ars.role_desc = 'SECONDARY'
	END

	DECLARE @Port INT

	SELECT @Port = local_tcp_port
	FROM sys.dm_exec_connections 
	WHERE session_id = @@spid

	INSERT INTO @Instance
	(
		InstanceName,
		ListenerName
	)
	SELECT CASE WHEN @Port IS NULL THEN @@SERVERNAME 
			ELSE @@SERVERNAME + ',' + CAST(@Port AS VARCHAR(4)) END AS InstanceName,
		   CASE WHEN @ListenerPort IS NULL THEN @ListenerName
			ELSE @ListenerName+ ',' + CAST(@ListenerPort AS VARCHAR(4)) END AS ListenerName

	RETURN
END

GO


