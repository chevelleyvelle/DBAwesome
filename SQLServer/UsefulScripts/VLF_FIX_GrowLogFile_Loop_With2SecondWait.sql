/* ------------------------------------------------------------------------------------------------------------------------------ /
	- This is for databases with only 1 log file.  
	- This is for use when doing a shrink and regrow to fix VLF problems
	- This grows in 8GB chunks until final desired size (@GoalSizeGB) is reached 
		- This takes into account the new (2014 and up) algorithm to split VLFS in final growth to keep even
			- If want to ignore algorithm and have smaller but many more VLFS then set @AlgorithmIgnore = 1
			- This will result in more overall VLFs but all will be equal sized until log file auto grows next time.
			--https://www.sqlskills.com/blogs/paul/important-change-vlf-creation-algorithm-sql-server-2014/

	User Parameters:  
		- @DbName SYSNAME --Set to the database you have shrunk and need to regrow the file
		- @GoalSizeGB INT --Set to the final size you want the log file to be
		- @AlgorithmIgnore BIT  --NULLable.  If NULL then defaults to 0 and let's SQL do it's thing.  
								   Once you hit the growth less than 1/8 of current log size adds 1 big VLF = 8GB
								   1 - Ignore and break up 8GB into 512 growths until file size reached.  Lots more growths and files, but even sized
								   0 - Use default SQL Algorithm (SQL 2014 up change)
/ ---------------------------------------------------------------------------------------------------------------------------- */
DECLARE @DbName SYSNAME 
	   ,@GoalSizeGB INT
	   ,@AlgorithmIgnore BIT

	SET @DbName = 'DBA'
	SET @GoalSizeGB = 10
	SET @AlgorithmIgnore = NULL

--Default AlgorithmIgnore to not ignore (0) IF NULL (Let SQL do it's thing)
IF @AlgorithmIgnore IS NULL
BEGIN
	SELECT @AlgorithmIgnore = 0
END

----other variables
DECLARE @GoalSizeMB INT = @GoalSizeGB * 1024
	   ,@FileName SYSNAME
	   ,@CurrSizeMB INT
	   ,@DesiredGrowthMB INT
	   ,@GrowthMB INT
	   ,@GrowthSize INT
	   ,@AlgorithmStart BIT 
	   ,@v_sql NVARCHAR(1000)
 
--Get initial settings
SELECT @CurrSizeMB = CONVERT(INT,FLOOR(size/128.0))
	  ,@FileName = [name]
	  ,@DesiredGrowthMB = 8192 --8GB growth as per recommended
FROM sys.master_files
WHERE database_id = DB_ID(@DbName) and [file_id] = 2

--Grow file with 2 seconds between each growth
WHILE @CurrSizeMB < @GoalSizeMB
BEGIN	
	--Set desired Growth settings algorithm for 2014+
	SELECT @AlgorithmStart = CASE WHEN CAST(@DesiredGrowthMB AS FLOAT)/ CAST(@CurrSizeMB AS FLOAT) <= '0.125' THEN 1 ELSE 0 END
	SELECT @GrowthMB = CASE WHEN @AlgorithmIgnore = 1 AND @AlgorithmStart = 0 AND @GoalSizeMB - @currsizeMB < @DesiredGrowthMB 
								THEN @GoalSizeMB - @currsizeMB 
							WHEN @AlgorithmIgnore = 1 AND @AlgorithmStart = 0 AND @GoalSizeMB - @currsizeMB >= @DesiredGrowthMB 
								THEN @DesiredGrowthMB 
							WHEN @AlgorithmIgnore = 1 AND @AlgorithmStart = 1 AND @GoalSizeMB - @currsizeMB < @DesiredGrowthMB/16 
								THEN @GoalSizeMB - @currsizeMB 
							WHEN @AlgorithmIgnore = 1 AND @AlgorithmStart = 1 AND @GoalSizeMB - @currsizeMB >= @DesiredGrowthMB/16 
								THEN  @DesiredGrowthMB/16 
							WHEN @AlgorithmIgnore = 0 AND @GoalSizeMB - @currsizeMB < @DesiredGrowthMB 
								THEN @GoalSizeMB - @currsizeMB 
								ELSE @DesiredGrowthMB 
						END 

	--SELECT @DesiredGrowthMB = CASE WHEN CAST(@DesiredGrowthMB AS FLOAT)/ CAST(@CurrSizeMB AS FLOAT) > '0.125' THEN @DesiredGrowthMB ELSE @DesiredGrowthMB/16 END 
	--SELECT @GrowthMB = CASE WHEN @AlgorithmIgnore = 1 AND CAST(@DesiredGrowthMB AS FLOAT)/ CAST(@CurrSizeMB AS FLOAT) > '0.125' THEN @DesiredGrowthMB 
	--		WHEN @AlgorithmIgnore = 1 AND CAST(@DesiredGrowthMB AS FLOAT)/ CAST(@CurrSizeMB AS FLOAT) <= '0.125' THEN @DesiredGrowthMB/16
	--		WHEN @AlgorithmIgnore = 0 AND @GoalSizeMB - @CurrSizeMB < @DesiredGrowthMB THEN @GoalSizeMB - @CurrSizeMB ELSE @DesiredGrowthMB END
	SELECT @GrowthSize = @CurrSizeMB + @GrowthMB
	SELECT @v_sql = N'ALTER DATABASE ['+@DbName+'] MODIFY FILE (Name='''+@FileName+''',Size='+CONVERT(NVARCHAR(10),@GrowthSize)+'MB);'
  
	PRINT @v_sql
 
	EXECUTE sp_executesql @v_sql
  
	WAITFOR DELAY '00:00:02';

    SELECT @CurrSizeMB = convert(int,floor(size/128.0))
	FROM sys.master_files
	WHERE database_id = DB_ID(@DbName) and [file_id] = 2

END