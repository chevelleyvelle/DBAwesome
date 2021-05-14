USE [DS_Utility]
GO


IF (SELECT OBJECT_ID ('usp_check_PrimaryServer','P')) IS NOT NULL
DROP PROCEDURE [dbo].[usp_check_PrimaryServer]
GO


CREATE PROCEDURE [dbo].[usp_check_PrimaryServer] (
	@JobName VARCHAR(150), 
	
	--If want to use specific db Mail profile from proc (optional)
	@MailProfile VARCHAR(100) = NULL, 
	
	--If want to send to specific email from proc (optional)
	@Email VARCHAR(100) = NULL, 

	--If more than one AG/Listener on server.  Use listener associated AG syncing the DB used in job steps (Optional)
	@ListenerName nvarchar(63) = NULL, 

	--If want to run on secondary node(s) only and not primary.  Would need to be read only operations against dbs being synced.
	--Will run on all Secondary instances belonging to the AG. (Optional)
	@RunOnSecondaryOnly BIT = NULL, 

	--If want to run on all nodes of an AG 
	--Use for jobs like collecting server stats to non AG-Synced dbs, or maintenance tasks. (Optional)
	@RunOnAllAGNodes BIT = NULL)
AS 
/* ========================================================================================
 Author:       CDurfey 
 Create date: 04/01/2021 
 Description: 
	This proc will allow jobs to be enabled on secondary nodes of an AG within SQL server
	Checks to see if Server is in a cluster or AG or is a stand alone server.
		* If stand alone server or WFCI (not AG), sets @Count=1 so job will run as primary node.
	Checks to see if server is primary and if so continue to next step else quit the job.
	 - Set as first step in jobs.
	   -  Upon failure, quit the job reporting success
	   -  Upon success, go to next step.
	If Server has multiple AGs/Listeners, can pass through optional @ListenerName.
	 - Pass through the ListenerName for the AG hosting the Database being referenced in the job.
---Job STEP CALL example
/*  GET THE CURRENT RUNNING JOBID, JOB NAME AND CURRENT STEP ID */
DECLARE @Job_Name NVARCHAR(128) 
SELECT @Job_Name =  name FROM msdb.dbo.sysjobs WHERE job_id = $(ESCAPE_SQUOTE(JOBID))

EXECUTE [DB_Name%].[dbo].[usp_check_PrimaryServer] @JobName= @Job_Name

On Success: Go to the next step
On Failure: Quit the job reporting success
=========================================================================================== */
BEGIN

DECLARE @Count INT = 0

IF @Email IS NULL
    SELECT @Email = 'testemail@testemail.com' --change as needed

IF @MailProfile IS NULL	
	SET @MailProfile = 'default' --change as needed

DECLARE @errSubject VARCHAR(150)
DECLARE @errBody VARCHAR(255)

SELECT @errSubject = '@@ServerName - @JobName Failed'
SELECT @errSubject = REPLACE(@errSubject, '@@ServerName', @@ServerName)
SELECT @errSubject = REPLACE(@errSubject, '@JobName', @JobName)

SELECT @errBody = @errSubject + '.  Error Determining Primary Server!  Check Job/Server' 

/*--------------------------------------------------------------------------------------------------/
	Default @RunOnSecondaryOnly = 0 if NULL 
	Set @RunOnSecondaryOnly = 0 if @RunOnAllAGNodes =1 passed in.  All Nodes takes precendence.  
/------------------------------------------------------------------------------------------------*/
IF @RunOnSecondaryOnly IS NULL OR (@RunOnAllAGNodes = 1 and @RunOnSecondaryOnly = 1)
BEGIN
	SET @RunOnSecondaryOnly = 0
END

IF @RunOnAllAGNodes IS NULL
BEGIN
	SET @RunOnAllAGNodes = 0
END


/* See if server is part of a cluster or AG.  If Stand alone or WFCI set @Count=1 */
IF NOT EXISTS 
(	
	SELECT 1 FROM sys.dm_hadr_availability_group_states --AG 
) 
BEGIN 
	SET @Count=1
END

IF @Count = 0 
BEGIN
	BEGIN TRY
		SELECT @Count = COUNT(*)
		FROM (
				SELECT 1 as Run
				FROM sys.dm_os_cluster_nodes --WFCI cluster
				UNION
				SELECT 1 AS Run
				FROM master.sys.availability_groups Groups
				INNER JOIN master.sys.availability_replicas Replicas 
					ON Groups.group_id = Replicas.group_id
				INNER JOIN master.sys.dm_hadr_availability_group_states States 
					ON Groups.group_id = States.group_id 
						AND Replicas.replica_server_name = @@SERVERNAME 
				INNER JOIN master.sys.availability_group_listeners Listeners 
					ON Groups.group_id = Listeners.group_id
				WHERE @RunOnSecondaryOnly = 0 AND  @RunOnAllAGNodes = 0 --Runs on Primary node only
					AND States.primary_replica = @@SERVERNAME --Is Primary node check
					AND (@ListenerName IS NULL OR Listeners.dns_name = @ListenerName) --Is Primary for the Listener if Listed incase of multiple listerners/AGs
				UNION 
				SELECT 1 AS Run
				FROM master.sys.availability_groups Groups
				INNER JOIN master.sys.availability_replicas Replicas 
					ON Groups.group_id = Replicas.group_id
				INNER JOIN master.sys.dm_hadr_availability_group_states States 
					ON Groups.group_id = States.group_id 
						AND Replicas.replica_server_name = @@SERVERNAME 
				INNER JOIN master.sys.availability_group_listeners Listeners 
					ON Groups.group_id = Listeners.group_id
				WHERE @RunOnSecondaryOnly = 1 --Only run on secondary and not primary
					AND States.primary_replica <> @@SERVERNAME --Is not the primary node check
					AND (@ListenerName IS NULL OR Listeners.dns_name = @ListenerName) --Is Secondary for the Listener if listed incase of multiple listerners/AGs
					AND Replicas.secondary_role_allow_connections_desc IN ('READ_ONLY','ALL') --Seconday is in fact readable, otherwise don't run
				UNION
				SELECT 1 AS Run
				FROM master.sys.availability_groups Groups
				INNER JOIN master.sys.availability_replicas Replicas 
					ON Groups.group_id = Replicas.group_id
				INNER JOIN master.sys.dm_hadr_availability_group_states States 
					ON Groups.group_id = States.group_id 
						AND Replicas.replica_server_name = @@SERVERNAME 
				INNER JOIN master.sys.availability_group_listeners Listeners 
					ON Groups.group_id = Listeners.group_id
				WHERE @RunOnAllAGNodes = 1  --Run on all Nodes
					AND (@ListenerName IS NULL OR Listeners.dns_name = @ListenerName) --Is Secondary for the Listener if listed incase of multiple listerners/AGs
					AND Replicas.secondary_role_allow_connections_desc IN ('READ_ONLY','ALL') --Seconday is in fact readable, otherwise don't run
			) a
	END TRY
	BEGIN CATCH
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = @MailProfile
		  , @recipients = @Email
		  , @subject = @errSubject
		  , @body = @errBody
	END CATCH
END

IF @Count = 0
    BEGIN 
        DECLARE @ErrorString VARCHAR(255)
		IF @RunOnSecondaryOnly = 1
		BEGIN
			SET @ErrorString= @@Servername
				+ ' is not currently the Secondary server or secondary is not readable in the availability group'
		END
		ELSE
		BEGIN
			SET @ErrorString= @@Servername
				+ ' is not currently the Primary server in the availability group'
		END

        RAISERROR (@ErrorString, 15, 1)
    END

END

GO


