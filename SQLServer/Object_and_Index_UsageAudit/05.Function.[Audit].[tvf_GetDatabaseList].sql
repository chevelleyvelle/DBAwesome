USE [DB_Name]
GO

CREATE FUNCTION [Audit].[tvf_GetDatabaseList] ()
RETURNS TABLE 
AS 
RETURN
	SELECT ConfigDatabaseID, DBName
    FROM Audit.ConfigDatabase
	WHERE ExcludeFromCleanup = 0 
		AND IsAGSecondary = 0 
		AND IsActive = 1;

GO


