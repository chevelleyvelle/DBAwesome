USE tempdb;

/*----------------------------------------------------------------------------------------------------------------------------------
Scripts out alter TempDB settings for values set
Scripts out Add Tempdb files for number of files set above what already exists.

	SET @DataSizeMB to value you want each TempDB Data file to be in (MB)
	SET @DataFileGrowthMB to value you want each TempDB data file Increments to be in (MB)   
		**0 = No autogrow
	SET @LogSizeMB to value you want TempDB Log file to be in (MB)
	SET @LogFileGrowthMB to value you want the TempDB Log file increments to be in (MB)
	SET @MaxTempDBFiles to value for the total number of TempDB files you want created.
		**This will add the files to that number with the matching settings to the other configurations using the variables above
----------------------------------------------------------------------------------------------------------------------------------*/

DECLARE @DataSizeMB VARCHAR(10) = 512
DECLARE @DataFileGrowthMB  VARCHAR(10) = 128

DECLARE @LogSizeMB  VARCHAR(10) = 128
DECLARE @LogFileGrowthMB  VARCHAR(10) = 64

DECLARE @MaxTempDBFiles INT = 4 --total Number of tempdb files to have 

SELECT 
	DB_NAME() AS DatabaseName,
	mf.[database_id] AS Database_id,
	mf.[name] AS [FileName],
	mf.[physical_name] AS PhysicalName,
	mf.[type_desc] AS FileType,
	CASE WHEN CEILING(mf.[size]/128) = 0 THEN 1 
		 ELSE CEILING(mf.[size]/128) END AS TotalSizeMB,
	CAST(FILEPROPERTY(mf.[name], 'SpaceUsed') AS INT)/128 AS UsedSpaceMB,
	CASE WHEN ceiling(mf.[size]/128)  = 0 THEN (1 - CAST(FILEPROPERTY(mf.[name], 'SpaceUsed') AS INT)/128) 
		 ELSE ((mf.[size]/128) - CAST(FILEPROPERTY(mf.[name], 'SpaceUsed') AS INT)/128) END AS AvailableSpaceMB,
	CASE WHEN mf.[is_percent_growth] = 1 THEN CAST(mf.[growth] AS VARCHAR(20)) + '%'
		 ELSE CAST(mf.[growth]*8/1024 AS varchar(20)) + 'MB' END AS GrowthUnits,   
	CASE WHEN mf.[max_size] = -1 THEN NULL 
		 WHEN mf.[max_size] = 268435456 THEN NULL   
		 ELSE mf.[max_size] END AS MaxFileSizeMB,
	CASE WHEN mf.[type_desc] = 'ROWS' THEN 'USE [master];' +  + CHAR(13) + CHAR(10) + 'ALTER DATABASE [tempdb] MODIFY FILE (NAME = N'''+ mf.[name] +''', SIZE = ' + @DataSizeMB + 'MB, FILEGROWTH = '+ @DataFileGrowthMB + 'MB);'+ CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
		 ELSE 'USE [master];' +  + CHAR(13) + CHAR(10) + 'ALTER DATABASE [tempdb] MODIFY FILE (NAME = N'''+ mf.[name] +''', SIZE = ' + @LogSizeMB + 'MB, FILEGROWTH = '+ @LogFileGrowthMB + 'MB);'+ CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) END AS AlterTempDB_Statement
FROM sys.master_files mf 
WHERE DB_NAME() = DB_NAME(mf.database_id)
ORDER BY mf.[file_id], [type_desc] DESC

DECLARE @CurrentDataFileCount INT
DECLARE @CurrentMaxFileNum VARCHAR(10)

		SELECT @CurrentDataFileCount = COUNT(1), 
			   @CurrentMaxFileNum = MAX(CASE WHEN PATINDEX('%[0-9]%',mf.[name]) >0 THEN SUBSTRING(mf.[name],PATINDEX('%[0-9]%',mf.[name]),2) ELSE 1 END)--Get last number on last file to increment from there.
		FROM sys.master_files mf 
		WHERE DB_NAME() = DB_NAME(mf.database_id)
		AND mf.type_desc = 'ROWS'

IF @CurrentDataFileCount < @MaxTempDBFiles
BEGIN
	--Get Current physical file name and logical file name to mimic for consistency
	DECLARE @PhysicalFileName VARCHAR(128)
	DECLARE @FileName VARCHAR(128)

	IF @CurrentDataFileCount = 1
		BEGIN 
			SET @PhysicalFileName = 'tempdev'
			SET @FileName = 'tempdev'
		END 
		ELSE
		BEGIN
			SELECT TOP (1) 
			@PhysicalFileName =  SUBSTRING(RIGHT(mf.physical_name,CHARINDEX('\',REVERSE(mf.physical_name))-1),1, LEN(RIGHT(mf.physical_name,CHARINDEX('\',REVERSE(mf.physical_name))-1))-PATINDEX('%[0-9]%',REVERSE(mf.physical_name))),
			@FileName = SUBSTRING(mf.[name],1,LEN(mf.[name])-PATINDEX('%[0-9]%',REVERSE(mf.[name])))
			FROM sys.master_files mf
			WHERE DB_NAME() = DB_NAME(mf.database_id)
			AND mf.[type_desc] = 'ROWS' AND mf.[file_id] > 1
			ORDER BY  mf.[file_id]
		END

	WHILE @CurrentDataFileCount <@MaxTempDBFiles
	BEGIN

		SET @CurrentMaxFileNum = @CurrentMaxFileNum+1

		SELECT 'USE [master];' +  + CHAR(13) + CHAR(10) + 
			   'ALTER DATABASE [tempdb] ADD FILE (NAME = N'''+ @FileName + @CurrentMaxFileNum + ''', FILENAME = N''' +  LEFT(mf.physical_name, (LEN(mf.physical_name) - CHARINDEX('\',REVERSE(mf.physical_name)))+1) + @PhysicalFileName +@CurrentMaxFileNum+'.ndf''' + 
			   ', SIZE = ' +@DataSizeMB + 'MB, FILEGROWTH = ' +@DataFileGrowthMB + 'MB);'
		FROM sys.master_files mf
		WHERE DB_NAME() = DB_NAME(mf.database_id)
		AND mf.name='tempdev'

		SET @CurrentDataFileCount = @CurrentDataFileCount + 1
	END
END
ELSE
BEGIN
	SELECT 'Already have TempDB File count.  No files to add'
END

