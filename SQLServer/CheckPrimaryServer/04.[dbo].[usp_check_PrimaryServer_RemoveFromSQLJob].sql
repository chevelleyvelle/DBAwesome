USE [DB_Name%]
GO

CREATE PROCEDURE [dbo].[usp_check_PrimaryServer_RemoveFromSQLJob] (
	@JobList AS dbo.tvp_SQLAgentJobList READONLY,

	--If want Print statements only (optional) Defaults to 0 when NULL
	@debug BIT = 0 )
AS
/* ========================================================================================
 Author:       CDurfey 
 Create date: 05/13/2021 
 Description: 
	Required parameter: 
		- @JobList AS dbo.tvp_SQLAgentJobList for list or single job name value.  
			- Name(s) of jobs you want to remove check primary from.		
	Optional parameters
		- @debug BIT 
			-Print statement instead of removing the step from the sql agent job
			-Defaults to 0 when NULL
	This proc will dynamically build the command Remove CheckPrimary step whichever step it is.
	Uses TVP dbo.tvp_SQLAgentJobList for that list of names, loops through and removes the step

Example call:

USE [DB_Name%]
GO 

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

EXECUTE [dbo].[usp_check_PrimaryServer_RemoveFromSQLJob] @JobList = @JobList
=========================================================================================== */
BEGIN 

SET NOCOUNT ON;

DECLARE @jobID uniqueidentifier
DECLARE @job_name sysname	
DECLARE @stepID INT

DECLARE @SQL AS NVARCHAR(MAX)
DECLARE @paramDef NVARCHAR(2000) 
SET @paramDef = '@jobID uniqueidentifier,  @stepID INT'

/* Default @debug = 0*/
IF @debug IS NULL
BEGIN
	SET @debug = 0
END


IF OBJECT_ID('tempdb..#jobs') IS NOT NULL
    DROP TABLE #jobs

CREATE TABLE #jobs
( 
	job_id UNIQUEIDENTIFIER,
	job_name sysname,
	step_id INT
);

INSERT INTO #jobs
SELECT j.job_id, j.[name] AS job_name, js.step_id
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id AND js.step_name = 'Check Primary Server'
INNER JOIN @JobList jl ON j.name = jl.job_name

WHILE (SELECT COUNT(1) FROM #jobs)>0
BEGIN 
	SELECT TOP 1 @jobID = job_id, @stepID = step_id
	FROM #jobs
	ORDER BY job_id

	SET @SQL =N'USE [msdb];
		EXEC msdb.dbo.sp_delete_jobstep @job_id= @jobID, @step_id= @stepID'

	IF @debug = 1
	BEGIN
		print REPLACE(REPLACE(@SQL, '@jobID', ''''+ CAST(@jobID AS VARCHAR(36))+''''), '@stepID', CAST(@stepID AS VARCHAR(10)))
	END
	ELSE
	BEGIN
		EXEC sp_executesql @SQL, @paramDef, @jobID = @jobID, @stepID = @stepID
	END
	
	DELETE FROM #jobs 
	WHERE job_id = @jobID

END

END