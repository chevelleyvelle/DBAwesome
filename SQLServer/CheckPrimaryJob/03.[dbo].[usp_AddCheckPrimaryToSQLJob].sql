USE DS_Utility
GO

CREATE PROCEDURE [dbo].[usp_check_PrimaryServer_AddToSQLJob] (
	@JobList AS dbo.tvp_SQLAgentJobList READONLY,
	
	--Database proc [dbo].[usp_check_PrimaryServer] lives in
	@StepDBName sysname,
	
	--If want to use specific db Mail profile from hardcoded in proc (optional)
	@MailProfile VARCHAR(100) = NULL,
	
	--If want to send to specific email from hardcoded in proc (optional)
	@Email VARCHAR(100) = NULL,

	--If more than one AG/Listener on server.  Use listener associated AG syncing the DB used in job steps (Optional)
	@ListenerName NVARCHAR(63) = NULL,

	--IF want to run on all readable nodes of an AG.  Use for jobs like collecting server stats to non AG-Synced dbs, or maintenance tasks. (Optional)
	@RunOnAllAGNodes BIT = NULL,

	--If want to job to run on secondary node(s) only and not primary.  Will set jobs to run on all readable Secondary instances belonging to the AG. (Optional)
	@RunOnSecondaryOnly BIT = NULL,

	--If want Print statements only (optional) Defaults to 0 when NULL
	@debug BIT = 0 )
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 05/13/2021 
 Description: 
	Required parameter: 
		- @JobList AS dbo.tvp_SQLAgentJobList for list or single job name value.  
			- Name(s) of Jobs you want to add check primary to.	
		- @StepDBName - Database proc [dbo].[usp_check_PrimaryServer] lives in.  Need for step to call
	Optional parameters all used in the proc dbo.usp_check_PrimaryServer except @debug.  
		- added so job step can be built with the parameters needed for the job list.
		- most jobs should only need jobname and it will set the job to only run on primary node
		- @MailProfile - mail profile to use for sending mail if want something other than what 
						 is hardcoded in usp_checkPrimaryServer.
		- @Email - Email to send failure to if want something other than what is hardcoded 
				   in usp_checkPrimaryServer.
		- @ListenerName - If more than 1 listener on the node.
		- @RunOnAllAGNodes - If want to run on primary and all readable secondary nodes
		- @RunOnSecondaryOnly - If want to run on all readable secondary nodes but not primary
		- @debug - print statement instead of adding the step to the sql agent job. Defaults to 0 when NULL

	This proc will dynamically build the command to call the proc dbo.usp_check_PrimaryServer
	with the parameters that proc accepts for your case.  
	Uses TVP dbo.tvp_SQLAgentJobList for that list of names, loops through and adds the step
	as step 1 to those jobs with
	On Success: Go to the next step
	On Failure: Quit the job reporting success

Example call for basic primary only run step:

USE [DB_Name%]
GO 

DECLARE @StepDBName sysname = 'DS_Utility'
DECLARE @JobList AS dbo.tvp_SQLAgentJobList;

INSERT INTO @JobList
SELECT j.[name] AS job_name
FROM msdb.dbo.sysjobs j
WHERE j.[name] IN 
(	
	'JobName1',
	'JobName2',
	'JobName3',
	'JobName4'
) 

EXECUTE [dbo].[usp_check_PrimaryServer_AddToSQLJob] @JobList = @JobList, @StepDBName = @StepDBName
=========================================================================================== */
BEGIN 

SET NOCOUNT ON;

DECLARE @jobID UNIQUEIDENTIFIER
DECLARE @job_name sysname	
DECLARE @jobCommand NVARCHAR(MAX) 
DECLARE @newLine CHAR(2) = CHAR(13) + CHAR(10)
DECLARE @SQL AS NVARCHAR(MAX)
DECLARE @paramDef NVARCHAR(2000) 
SET @paramDef = '@jobID uniqueidentifier, @jobCommand NVARCHAR(MAX)'

/* Default @debug = 0*/
IF @debug IS NULL
BEGIN
	SET @debug = 0
END

SET @jobCommand = N'DECLARE @Job_Name NVARCHAR(128)' + @newLine + 
	N'SELECT @Job_Name =  name FROM msdb.dbo.sysjobs WHERE job_id = $(ESCAPE_SQUOTE(JOBID))' + @newLine + @newLine +
	N'EXECUTE ' + QUOTENAME(@StepDBName) + N'.[dbo].[usp_check_PrimaryServer] @JobName= @Job_Name'

IF NULLIF(@MailProfile,'') IS NOT NULL
BEGIN
	--SET @paramDef = @paramDef + ', @MailProfile VARCHAR(100)'
	SET @jobCommand = @jobCommand + N', @MailProfile = ''' + @MailProfile +''''
END

IF NULLIF(@Email,'') IS NOT NULL
BEGIN
	--SET @paramDef = @paramDef + ', @Email VARCHAR(100)'
	SET @jobCommand = @jobCommand + N', @Email = ''' + @Email +''''
END

IF @ListenerName IS NOT NULL
BEGIN
	--SET @paramDef = @paramDef + ', @ListenerName NVARCHAR(63)'
	SET @jobCommand = @jobCommand + N', @ListenerName = ''' + @ListenerName +''''
END

IF @RunOnAllAGNodes IS NOT NULL
BEGIN
	--SET @paramDef = @paramDef + ', @RunOnAllAGNodes BIT'
	SET @jobCommand = @jobCommand + N', @RunOnAllAGNodes = ''' + CAST(@RunOnAllAGNodes AS CHAR(1)) +''''
END

IF @RunOnSecondaryOnly IS NOT NULL
BEGIN
	--SET @paramDef = @paramDef + ', @RunOnSecondariesOnly BIT'
	SET @jobCommand = @jobCommand + N', @RunOnSecondaryOnly = ''' + CAST(@RunOnSecondaryOnly AS CHAR(1)) +''''
END


IF OBJECT_ID('tempdb..#jobs') IS NOT NULL
    DROP TABLE #jobs

CREATE TABLE #jobs
( 
	job_id UNIQUEIDENTIFIER,
	job_name sysname
);

INSERT INTO #jobs
SELECT j.job_id, j.[name] AS job_name
FROM msdb.dbo.sysjobs j
INNER JOIN @JobList jl ON j.name = jl.job_name
AND NOT EXISTS (	SELECT js.job_id 
					FROM msdb.dbo.sysjobsteps js 
					WHERE j.job_id = js.job_id AND js.step_name = 'Check Primary'
			   )

WHILE (SELECT COUNT(1) FROM #jobs)>0
BEGIN 
	SELECT TOP 1 @jobID = job_id
	FROM #jobs
	ORDER BY job_id

	SET @SQL =N'USE [msdb];

	EXEC msdb.dbo.sp_add_jobstep @job_id= @jobID, @step_name=N''Check Primary'', 
			@step_id=1, 
			@cmdexec_success_code=0, 
			@on_success_action=3, 
			@on_fail_action=1, 
			@retry_attempts=0, 
			@retry_interval=0, 
			@os_run_priority=0, @subsystem=N''TSQL'', 
			@command= @jobCommand, 
			@database_name=N''master'', 
			@flags=0;'

	IF @debug = 1
	BEGIN
		PRINT REPLACE(REPLACE(@SQL, '@jobID', ''''+ CAST(@jobID AS VARCHAR(36))+''''),'@jobCommand', @jobCommand)
	END
	ELSE
	BEGIN
		EXEC sp_executesql @SQL, @paramDef, @jobID = @jobID, @jobCommand = @jobCommand
	END
	
	DELETE FROM #jobs 
	WHERE job_id = @jobID

END

END

