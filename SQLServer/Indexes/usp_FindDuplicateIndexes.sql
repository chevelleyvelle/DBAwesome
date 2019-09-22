CREATE PROCEDURE dbo.usp_FindDuplicateIndexes
AS 
/* ========================================================================================
 Author:       CDurfey 
 Create date: 09/22/2019 
 Description: 
	 - For every user db find any tables and the exact duplicate indexes
	 - Use this for analysis to clean up duplicate indexes.
	 - Will want to look for query plan cache where index hints are used to verify nothing
		in cache references the index you may want to drop.
	 - May want to look at index usage of the index you want to drop.
 exec dbo.usp_FindExactDuplicateIndexes
=========================================================================================== */
BEGIN
	SET NOCOUNT ON;

	IF OBJECT_ID('tempdb..#DupeIndex') IS NOT NULL
	    DROP TABLE #DupeIndex

	CREATE TABLE #DupeIndex 
	(
		DatabaseName VARCHAR(100) NULL,
		ObjectID INT NULL,
		[Table] VARCHAR(250) NULL,
		[IndexID] INT NULL,
		[Index] VARCHAR(500) NULL,
		ExactDuplicateIndexID INT NULL,
		ExactDuplicate VARCHAR(500) NULL,
		IndexDDL NVARCHAR(MAX) NULL,
		ExactDuplicateDDL VARCHAR(MAX) NULL
	)
		
	--exact duplicates
	DECLARE @Query NVARCHAR(MAX) = 
	'WITH indexcols AS 
	(  
		SELECT object_id AS id, index_id AS indid, name, 
		( 
			SELECT CASE keyno WHEN 0 THEN NULL ELSE colid END AS [data()] 
			FROM sys.sysindexkeys AS k 
			WHERE k.id = i.object_id 
			AND k.indid = i.index_id 
			ORDER BY keyno, colid 
			FOR XML PATH('''')  
		) AS cols, 
		( 
			SELECT CASE keyno WHEN 0 THEN colid ELSE NULL END AS [data()] 
			FROM sys.sysindexkeys AS k  
			WHERE k.id = i.object_id 
			AND k.indid = i.index_id 
			ORDER BY colid 
			FOR XML PATH('''') 
		) AS inc
		FROM sys.indexes AS i 
	) 
	SELECT DB_NAME() AS DatabaseName, c1.id AS ''ObjectID'', object_schema_name(c1.id) + ''.'' + object_name(c1.id) as ''Table'',
		c1.indid AS ''IndexID'', c1.name as ''Index'', 
		c2.indid AS ''ExactDuplicateIndexID'', c2.name as ''ExactDuplicate''
	FROM indexcols AS c1 
	JOIN indexcols AS c2 ON c1.id = c2.id AND c1.indid < c2.indid AND c1.cols = c2.cols AND c1.inc = c2.inc;'

	 DECLARE curDB CURSOR FORWARD_ONLY STATIC FOR   
		SELECT [name]    
		FROM master..sysdatabases   
		WHERE [name] NOT IN ('model', 'tempdb', 'master','msdb')   
		ORDER BY [name]   
         
	 DECLARE @DB sysname    
   
	 OPEN curDB    
	 FETCH NEXT FROM curDB INTO @DB    
	 WHILE @@FETCH_STATUS = 0    
		BEGIN   
		 DECLARE @SQL NVARCHAR(MAX) = 'USE [' + @DB +']; ' + @Query
		 BEGIN TRY  
			INSERT INTO #DupeIndex
			(DatabaseName, ObjectID, [Table], IndexID, [Index], ExactDuplicateIndexID, ExactDuplicate)
		   exec sp_executesql @SQL  
		 END TRY  
		 BEGIN CATCH  
		 END CATCH  
		 FETCH NEXT FROM curDB INTO @DB    
		END   
        
	 CLOSE curDB    
	 DEALLOCATE curDB  

   DECLARE @DBName VARCHAR(100),
		   @ObjectID VARCHAR(10),
		   @IndexID VARCHAR(10),
		   @DupeIndexID VARCHAR(500)

   	DECLARE cur_IndexDDL CURSOR FOR
		SELECT DatabaseName, CAST(ObjectID AS VARCHAR(10)), CAST(IndexID AS VARCHAR(10)), CAST(ExactDuplicateIndexID AS VARCHAR(10))
		FROM #DupeIndex
		ORDER BY DatabaseName, ObjectID

	OPEN cur_IndexDDL;
	FETCH cur_IndexDDL
	INTO @DBName, @ObjectID, @IndexID, @DupeIndexID

	WHILE @@FETCH_STATUS = 0
	BEGIN 
	 DECLARE @IQuery NVARCHAR(MAX)


	 SET @IQuery = N'
		DECLARE @DDL NVARCHAR(MAX) = N''''
		IF OBJECT_ID(''tempdb..#index_column'') IS NOT NULL
		DROP TABLE #index_column
    
		SELECT 
			  ic.[object_id]
			, ic.index_id
			, ic.is_descending_key
			, ic.is_included_column
			, c.name
		INTO #index_column
		FROM sys.index_columns ic WITH (NOWAIT)
		JOIN sys.columns c WITH (NOWAIT) ON ic.[object_id] = c.[object_id] AND ic.column_id = c.column_id 
		WHERE ic.[object_id] = '+ @ObjectID +' and ic.index_id = '+@IndexID+'


SELECT @DDL = 
--------------------- INDEXES ----------------------------------------------------------------------------------------------------------
    CAST(
        ISNULL(((SELECT
             NCHAR(13) + N''CREATE'' + CASE WHEN i.is_unique = 1 THEN N'' UNIQUE '' ELSE N'' '' END 
                    + i.type_desc + N'' INDEX '' + quotename(i.name) + N'' ON '' + + quotename(OBJECT_schema_name('+ @ObjectID +')) + N''.'' + quotename(OBJECT_NAME('+ @ObjectID +')) + + N'' ('' +
                    STUFF((
                    SELECT N'', '' + quotename(c.name) + N'''' + CASE WHEN c.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                    FROM #index_column c
                    WHERE c.is_included_column = 0
                        AND c.index_id = i.index_id
                    FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') + N'')''  
                    + ISNULL(NCHAR(13) + N''INCLUDE ('' + 
                        STUFF((
                        SELECT N'', '' + quotename(c.name) + N''''
                        FROM #index_column c
                        WHERE c.is_included_column = 1
                            AND c.index_id = i.index_id
                        FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') + N'')'', N'''')  + NCHAR(13)
            FROM sys.indexes i WITH (NOWAIT)
            WHERE i.[object_id] = '+ @ObjectID +'
                AND i.[type] in (1,2)
            FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)'')
        ), N'''')
    as nvarchar(max))

	/* Update #ObjectDDL */
	UPDATE d
	SET IndexDDL = @DDL
	FROM #DupeIndex d
	WHERE DatabaseName = DB_NAME() and ObjectID = '+@ObjectID+' AND IndexID = '+@IndexID+''

	DECLARE @ISQL NVARCHAR(MAX) = 'USE [' + @DBName +']; ' + @IQuery
	 exec sp_executesql @ISQL  

	---------------------------------------------------------------
	 DECLARE @DQuery NVARCHAR(MAX)
	 SET @DQuery = N'
		DECLARE @DDL NVARCHAR(MAX) = N''''
		IF OBJECT_ID(''tempdb..#index_column'') IS NOT NULL
		DROP TABLE #index_column
    
		SELECT 
			  ic.[object_id]
			, ic.index_id
			, ic.is_descending_key
			, ic.is_included_column
			, c.name
		INTO #index_column
		FROM sys.index_columns ic WITH (NOWAIT)
		JOIN sys.columns c WITH (NOWAIT) ON ic.[object_id] = c.[object_id] AND ic.column_id = c.column_id 
		WHERE ic.[object_id] = '+ @ObjectID +' and ic.index_id = '+@DupeIndexID+'


SELECT @DDL = 
--------------------- INDEXES ----------------------------------------------------------------------------------------------------------
    CAST(
        ISNULL(((SELECT
             NCHAR(13) + N''CREATE'' + CASE WHEN i.is_unique = 1 THEN N'' UNIQUE '' ELSE N'' '' END 
                    + i.type_desc + N'' INDEX '' + quotename(i.name) + N'' ON '' + + quotename(OBJECT_schema_name('+ @ObjectID +')) + N''.'' + quotename(OBJECT_NAME('+ @ObjectID +')) + + N'' ('' +
                    STUFF((
                    SELECT N'', '' + quotename(c.name) + N'''' + CASE WHEN c.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                    FROM #index_column c
                    WHERE c.is_included_column = 0
                        AND c.index_id = i.index_id
                    FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') + N'')''  
                    + ISNULL(NCHAR(13) + N''INCLUDE ('' + 
                        STUFF((
                        SELECT N'', '' + quotename(c.name) + N''''
                        FROM #index_column c
                        WHERE c.is_included_column = 1
                            AND c.index_id = i.index_id
                        FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') + N'')'', N'''')  + NCHAR(13)
            FROM sys.indexes i WITH (NOWAIT)
            WHERE i.[object_id] = '+ @ObjectID +'
                AND i.[type] in (1,2)
            FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)'')
        ), N'''')
    as nvarchar(max))



	/* Update #ObjectDDL */
	UPDATE d
	SET ExactDuplicateDDL = @DDL
	FROM #DupeIndex d
	WHERE DatabaseName = DB_NAME() and ObjectID = '+@ObjectID+' AND ExactDuplicateIndexID = '+@DupeIndexID+''
	

	DECLARE @DSQL NVARCHAR(MAX) = 'USE [' + @DBName +']; ' + @DQuery
	 exec sp_executesql @DSQL  

	FETCH NEXT FROM cur_IndexDDL
    INTO @DBName, @ObjectID, @IndexID, @DupeIndexID
	END
	CLOSE cur_IndexDDL;
	DEALLOCATE cur_IndexDDL;

	SELECT DatabaseName,
           ObjectID,
           [Table],
           IndexID,
           [Index],
           ExactDuplicateIndexID,
           ExactDuplicate,
           IndexDDL,
           ExactDuplicateDDL
	FROM #DupeIndex

END
