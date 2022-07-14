
CREATE PROCEDURE dbo.usp_FailedSQLAgentJobs_Email @LookBackHours INT = 24, @RecipientList VARCHAR(MAX), @ProfileName NVARCHAR(128) = NULL, @GetAllFailingJobSteps BIT = 0, @TestMode BIT = 0
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 07/14/2022 
 Description: 
	 - Get all failed SQL Agent Jobs for the last day (from time of job running)
	 - Email list of failed jobs to @RecipientList 
	 - Need to supply the SQL Mail profile name or it will default to 'default'
	   Will verify the profile exists or throw an error requiring the correct profile name.

	 - This is used because the majority of our SQL jobs do not have notification on failure.
	   Jobs are not set to email on failure due to how often it would email potentially if we had consistent failures.
       A consistent failure would cause Email to blow up before a change could be made to fix it or stop alerting.  
	   While it is bad that a job could silently fail for a while, I believe there are other jobs that monitor Queue levels 
	   and other things to see if something begins to backlog.


	 -Parameters: @LookBackHours = 24 (DEFAULT) --Number of hours you want the job to look back for failures from GETDATE().  This should coincide with how often you run the job.  
							i.e. run daily set to 24, run weekly set to 168.  Or set to whatever value for running one off research with @TestMode = 1
				  @RecipientList = 'Email@List.Here' --semi-colon delimited list 'email1@email;email2@email'
				  @ProfileName = 'default' --If this is NULL it will default to 'default' as most companies have a default set
				  @GetAllFailingJobSteps = 0 (DEFAULT) --Will only pull jobs if job final outcome was failure.
				  -or-
				  @GetAllFailingJobSteps = 1 --This will pull all job steps that failed see details below *
					*If a job has steps that fail, but on failure continue to next step, and the job outcome is successful,
						you won't get the email for those steps, unless this flag is set to 1.  
					 When NULL or 0 only emails jobs where the final outcome is Failed.
				  @TestMode = 0 (DEFAULT) - Will send the email
				  -or-
				  @TestMode = 1 Will not send the email, but will return the results for viewing.  Great for 1 off research.
 
 Modification: 
 EXEC dbo.usp_FailedSQLAgentJobs_Email @RecipientList = 'Email@List.Here', @ProfileName = NULL, @GetAllFailingJobSteps = 0 @TestMode = 0
=========================================================================================== */
BEGIN
	SET NOCOUNT ON

	DECLARE @RunTimeStart DATETIME
	DECLARE @RunTimeEnd DATETIME

		SET @RunTimeStart = DATEADD(HOUR, -@LookBackHours, GETDATE())
		SET @RunTimeEnd = GETDATE()

	/*Set defaults in case overwritten defaults with NULL*/
	/* Get only jobs where the job outcome is failed */
	IF @GetAllFailingJobSteps IS NULL
	BEGIN
		SET @GetAllFailingJobSteps = 0
	END

	/* Send the email of job failures*/
	IF @TestMode IS NULL
	BEGIN
		SET @TestMode = 0
	END


	CREATE TABLE #FailedJobs
	(
	[JobName] NVARCHAR(128) NOT NULL,
	[StepName] NVARCHAR(128) NOT NULL,
	[RunDateTime] DATETIME,
	[RunDuration (DD:HH:MM:SS)] NVARCHAR(100),
	[Message] NVARCHAR(4000),
	[Retries_Attempted] INT NOT NULL,
	[Server] NVARCHAR(128) NOT NULL,
	[SQL_MessageId] INT NOT NULL,
	[SQL_Severity] INT NOT NULL
	)

	IF @GetAllFailingJobSteps = 1
	BEGIN

		INSERT INTO #FailedJobs
		(
			[JobName],
			[StepName],
			[RunDateTime],
			[RunDuration (DD:HH:MM:SS)],
			[Message],
			[Retries_Attempted],
			[Server],
			[SQL_MessageId],
			[SQL_Severity]
		)
		--look for failed jobs
		SELECT j.[name] AS [JobName], 
			s.step_name AS [StepName],  
			msdb.dbo.agent_datetime(run_date, run_time) AS [RunDateTime],
			STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(h.run_duration AS VARCHAR(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':') AS [RunDuration (DD:HH:MM:SS)],
			h.[message] AS [Message],
			h.retries_attempted AS [Retries_Attempted], 
			h.[server] AS [Server],
			h.sql_message_id AS [SQL_MessageId], 
			h.sql_severity AS [SQL_Severity]
		FROM msdb.dbo.sysjobs j (NOLOCK)
		INNER JOIN msdb.dbo.sysjobsteps s (NOLOCK)
			ON j.job_id = s.job_id
		INNER JOIN msdb.dbo.sysjobhistory h (NOLOCK)
			ON s.job_id = h.job_id 
			AND s.step_id = h.step_id 
			AND h.step_id <> 0
		WHERE 
			msdb.dbo.agent_datetime(run_date, run_time) BETWEEN @RunTimeStart and @RunTimeEnd 
			AND h.run_status=0
	 END

	 IF @GetAllFailingJobSteps = 0
	 BEGIN 
		
		CREATE TABLE #FailedJobIds
		(job_id UNIQUEIDENTIFIER)

		INSERT INTO #FailedJobIds
		(job_id)
		SELECT DISTINCT h.job_id
		FROM msdb.dbo.sysjobhistory h (NOLOCK)
		WHERE 
			msdb.dbo.agent_datetime(run_date, run_time) BETWEEN @RunTimeStart and @RunTimeEnd 
			AND h.run_status=0
			AND step_id = 0 --Job outcome failed

		INSERT INTO #FailedJobs
		(
			[JobName],
			[StepName],
			[RunDateTime],
			[RunDuration (DD:HH:MM:SS)],
			[Message],
			[Retries_Attempted],
			[Server],
			[SQL_MessageId],
			[SQL_Severity]
		)
		SELECT j.[name] AS [JobName], 
			s.step_name AS [StepName],  
			msdb.dbo.agent_datetime(run_date, run_time) AS [RunDateTime],
			STUFF(STUFF(STUFF(RIGHT(REPLICATE('0', 8) + CAST(h.run_duration AS VARCHAR(8)), 8), 3, 0, ':'), 6, 0, ':'), 9, 0, ':') AS [RunDuration (DD:HH:MM:SS)],
			h.[message] AS [Message],
			h.retries_attempted AS [Retries_Attempted], 
			h.[server] AS [Server],
			h.sql_message_id AS [SQL_MessageId], 
			h.sql_severity AS [SQL_Severity]
		FROM #FailedJobIds fjid
		INNER JOIN 	msdb.dbo.sysjobs j (NOLOCK)
			ON fjid.job_id = j.job_id
		INNER JOIN msdb.dbo.sysjobsteps s (NOLOCK)
			ON j.job_id = s.job_id
		INNER JOIN msdb.dbo.sysjobhistory h (NOLOCK)
			ON s.job_id = h.job_id 
			AND s.step_id = h.step_id 
			AND h.step_id <> 0
		WHERE 
			msdb.dbo.agent_datetime(run_date, run_time) BETWEEN @RunTimeStart and @RunTimeEnd 
			AND h.run_status=0
	 END

	 IF @TestMode = 1
	 BEGIN
		SELECT [JobName],
               [StepName],
               [RunDateTime],
               [RunDuration (DD:HH:MM:SS)],
               [Message],
               [Retries_Attempted],
               [Server],
			   [SQL_MessageId],
               [SQL_Severity]
		FROM #FailedJobs
		ORDER BY [JobName], [RunDateTime]
	END
	ELSE
	BEGIN

		/*Set Profile default and verify profile exists*/
		DECLARE @err_msg VARCHAR(1000);

		IF @ProfileName IS NULL
		BEGIN
			SET @ProfileName = 'default'
		END

		BEGIN TRY

			IF NOT EXISTS 
				(
					SELECT   
						ProfileName = smp.name  
					FROM msdb.dbo.sysmail_account sma  (NOLOCK)
						INNER JOIN msdb.dbo.sysmail_profileaccount smpa (NOLOCK) ON sma.account_id = smpa.account_id  
						INNER JOIN msdb.dbo.sysmail_profile smp (NOLOCK) ON smpa.profile_id = smp.profile_id  
					WHERE smp.name = @ProfileName
				) 
			BEGIN
				SET @err_msg = 'Mail Profile ' + QUOTENAME(@ProfileName) + ' does not exist on server ' + @@SERVERNAME + '.  Please verify profile name and try again.';
				THROW 50000, @err_msg,1
			END
		END TRY
		BEGIN CATCH

			IF @@trancount > 0
				ROLLBACK TRANSACTION;
			DECLARE @Message1 NVARCHAR(2048) = ERROR_MESSAGE(),
					@Severity1 INT = ERROR_SEVERITY(),
					@State1 INT = ERROR_STATE()

		   RAISERROR (@Message1, @Severity1, @State1)
		   RETURN -1
		END CATCH;
	

		/* CREATE AND SEND MESSAGE */
		DECLARE @Listener sysname
			SELECT @Listener = agl.dns_name 
			FROM sys.availability_group_listeners agl
			JOIN sys.availability_replicas agr ON agr.group_id = agl.group_id
			JOIN sys.dm_hadr_availability_replica_states AS agrs ON agrs.replica_id = agr.replica_id
			WHERE agr.replica_server_name = @@SERVERNAME AND agrs.role_desc = 'PRIMARY'

		DECLARE @Server sysname 
		SELECT @Server = CASE WHEN @Listener IS NOT NULL THEN @@SERVERNAME + ' (ListenerName:'+ @Listener + ')' ELSE @@SERVERNAME END

		DECLARE @EmailSubject VARCHAR (250) 
			SET @EmailSubject = @Server + ' - Failed SQL Jobs'

		IF EXISTS (SELECT TOP 1 1 FROM #FailedJobs)
		BEGIN 

			CREATE TABLE #MessageTemp 
			([Message] VARCHAR(250))
		
			IF @GetAllFailingJobSteps = 0
			BEGIN
				INSERT INTO #MessageTemp
				([Message])
					SELECT 'The following Jobs failed since ' + CONVERT(VARCHAR, @RunTimeStart, 109)  +'.' AS Message
					UNION
					SELECT 'Please look over these failures to see if more investigation is needed.' AS Message
			END
			ELSE
			BEGIN
				INSERT INTO #MessageTemp
				([Message])
					SELECT 'The following Jobs/Job Steps failed since ' + CONVERT(VARCHAR, @RunTimeStart, 109)  +'.' AS Message
					UNION
					SELECT 'Please look over failures to see if more investigation is needed.' AS Message
					UNION
					SELECT 'These steps may have failed, but jobs completed successfully if set to ''On failure continue to next step''.' AS Message
			END

			DECLARE @MessageHTML  NVARCHAR(MAX)

				SET @MessageHTML =
					N'<table border="0">' +
					N'<tr><th>Message</th></tr>' +
					CAST ( ( SELECT td = Message,''
							 FROM #MessageTemp
							  FOR XML PATH('tr'), TYPE 
					) AS NVARCHAR(MAX) ) +
					N'</table>'
		
			DECLARE @tableHTML  NVARCHAR(MAX) ;
				SET @tableHTML = 
					N'<H1>Failed Jobs and RunTimes</H1>' +
					N'<table border="1">' +
					N'<tr><th>JobName</th><th>StepName</th>' +
					N'<th>RunDateTime</th><th>RunDuration (DD:HH:MM:SS)</th>'+
					N'<th>SQL_MessageId</th><th>SQL_Severity</th>'+
					N'<th>Message</th>'+'<th>Retries_Attempted</th>'+'<th>Server</th></tr>'+
					CAST ( ( SELECT td = [JobName], '',
									td = [StepName], '',
									td = [RunDateTime], '',
									td = [RunDuration (DD:HH:MM:SS)], '',
									td = [Message], '',
									td = [Retries_Attempted], '',
									td = [Server], '',
									td = [SQL_MessageId], '',
									td = [SQL_Severity], ''
							  FROM #FailedJobs
							  ORDER BY [JobName], [RunDateTime]
							  FOR XML PATH('tr'), TYPE 
					) AS NVARCHAR(MAX) ) +
					N'</table>' ;

			DECLARE @Mergedtable NVARCHAR(MAX) ;
				SET @Mergedtable = @MessageHTML + @tableHTML

			EXEC msdb.dbo.sp_send_dbmail 
				@profile_name = @ProfileName,
				@recipients= @RecipientList,
				@subject = @EmailSubject,
				@body = @Mergedtable,
				@importance = 'High',
				@body_format = 'HTML' ;

		END
	END
END
GO