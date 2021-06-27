USE [DbMaintenance]
GO

/****** Object:  UserDefinedFunction [Audit].[tvf_GetDatabaseList]    Script Date: 6/16/2021 4:15:25 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [Audit].[tvf_GetDatabaseList] ()
RETURNS TABLE 
AS 
RETURN

	SELECT ConfigDatabaseID, DBName
    FROM [Audit].ConfigDatabase
	WHERE ExcludeFromCleanup = 0 
		AND IsAGSecondary = 0 
		AND IsActive = 1
	UNION
	SELECT ConfigDatabaseID, DBName
    FROM [Audit].ConfigDatabase
	WHERE ExcludeFromCleanup = 0 
		AND IsAGSecondary = 1 
		AND IsReadableSecondary = 1
		AND IsActive = 1;


GO


