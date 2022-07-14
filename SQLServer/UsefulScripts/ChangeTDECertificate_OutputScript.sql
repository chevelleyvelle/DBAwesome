/*------------------------------------------------------------------------------------------------------------------------
	- Dynamic Script that give script to switch out TDE Certificate for TDE encrypted databases.
		- Will not run anything, only queries data to output a script.
		- Run in Results to Text mode to create a script.  
		- Some steps require changing connection.  Run in pieces.  Read through
        - Need to run on any log shipped/ag secondary for any databases not log shipped/in AG to get the DB cert change scripts.
	
	User Parameters needed for script:
		@CertName --The name of your new certificate (i.e. 'TDE2022_Cert')
		@CertSubject --Subject for the Cert (i.e 'Prod TDE Cert')
		@Password --Your secure password to use for the encryption cert and pk backup.  MAKE SURE YOU STORE THIS
		@BackupFilePath --Local path on primary server you will bacup you cert and pk.  MAKE SURE YOU STORE THESE SOMEWHERE
		@RestoreFilePath  --Local path on the secondary or other server you will copy the cert and pk to for the restore of it.

	Outputs Scripts:
	 - CREATE CERTIFICATE
	 - BACKUP CERTIFICATE/PRIVATE KEY
	 - CREATE CERTIFICATE ON SECONDARY SERVER FROM BACKUP OF PRIMARY
		- Needs to be done in log shipped or AG environment before proceeding with cert change.
	 - Change Encryption cert for each database. 
	    - Need to run on any log shipped/ag secondary for any databases not log shipped/in AG
 -------------------------------------------------------------------------------------------------------------------*/
USE [master]
GO

SET NOCOUNT ON;

/* User Variables */
DECLARE @CertName NVARCHAR(128) = 'SQLPROD_YYYYTDE_Cert' /* Name you want for the Cerificate */
DECLARE @CertSubject nvarchar(4000) = 'Prod TDE Cert YYYY' /* Certificate subject */
DECLARE @Password NVARCHAR(60) = 'SecurePasswordHERE' /* Password to use for encryption.  Store this in a vault!! Clear out from script if saving */
DECLARE @BackupFilePath NVARCHAR(200) = 'C:\SQLBackup' /* Local path to backup certificate to */
DECLARE @RestoreFilePath NVARCHAR(200) = 'C:\Backup' /* Local path to Restore certificate from if puting on another node of AG or server */

/* Script Variables */
DECLARE @Cert_BkFile NVARCHAR(60)
DECLARE @CertPK_BkFile NVARCHAR(60)
DECLARE @Cert_RestoreFile NVARCHAR(60)
DECLARE @CertPK_RestoreFile NVARCHAR(60)
DECLARE @CreateCertSQL NVARCHAR(MAX)
DECLARE @BackupCertSQL NVARCHAR(MAX)
DECLARE @RestoreCertSQL NVARCHAR(MAX)
DECLARE @AlterDbEncryptionKeySQL NVARCHAR(MAX)

/* Verify paths have \ at end */
IF RIGHT(@BackupFilePath,1) <> '\'
BEGIN 
	SET @BackupFilePath = @BackupFilePath +'\'
END

IF RIGHT(@RestoreFilePath,1) <> '\'
BEGIN 
	SET @RestoreFilePath = @RestoreFilePath +'\'
END

--SELECT @BackupFilePath AS BackupFilePath, @RestoreFilePath AS RestoreFilePath --Testing

/* Set the full backup location and file for backup or Restore */
SET @Cert_BkFile = @BackupFilePath + @CertName + '.cer'
SET @CertPK_BkFile = @BackupFilePath + @CertName + '.pvk'

SET @Cert_RestoreFile = @RestoreFilePath + @CertName + '.cer'
SET @CertPK_RestoreFile = @RestoreFilePath + @CertName + '.pvk'

--SELECT @Cert_BkFile AS CertBackupFile, @CertPK_BkFile as CertPrivateKeyBackupFile --Testing
--SELECT @Cert_RestoreFile AS CertRestoreFile, @CertPK_RestoreFile AS CertPrivateKeyRestoreFile --Testing

SET @CreateCertSQL = 
N'USE [master]; ' + CHAR(13) + CHAR(10) 
+ N'CREATE CERTIFICATE ' + QUOTENAME(@CertName) + CHAR(13) + CHAR(10)
+ N'WITH SUBJECT = ''' + @CertSubject + ''';'

SELECT '--Create the New TDE Cert on the Primary server'
UNION
SELECT @CreateCertSQL AS Create_New_TDE_Cert

SET @BackupCertSQL = 
N'USE [master]; ' + CHAR(13) + CHAR(10) 
+ N'BACKUP CERTIFICATE ' +  QUOTENAME(@CertName) + CHAR(13) + CHAR(10)
+ N'TO FILE = ''' + @Cert_BkFile + N'''' + CHAR(13) + CHAR(10)
+ N'WITH PRIVATE KEY (FILE = ''' + @CertPK_BkFile + N''', ENCRYPTION BY PASSWORD = ''' + @Password + N''');'

SELECT '--Backup the Cert and Private Key to local path'
UNION
SELECT @BackupCertSQL AS BackupNewTDECert_and_PrivateKey

SET @RestoreCertSQL = 
N'USE [master]; ' + CHAR(13) + CHAR(10) 
+ N'CREATE CERTIFICATE ' +  QUOTENAME(@CertName) + CHAR(13) + CHAR(10)
+ N'FROM FILE = ''' + @Cert_RestoreFile + N'''' + CHAR(13) + CHAR(10)
+ N'WITH PRIVATE KEY (FILE = ''' + @CertPK_RestoreFile + N''', DECRYPTION BY PASSWORD = ''' + @Password + N''');'

SELECT '--Create the certificate on the secondary from the cert and key files by running script below.'
UNION SELECT '--If Restoring to another server (secondary node), copy backup files of Private Key and Cert to RestoreFilePath.'
UNION SELECT @RestoreCertSQL AS RestorTDECertTo_otherNodes


/* ----------------------------------------------------------------------------------
	Get all databases that are currently TDE Encrypted to change the certificate 
	Encrypted, Encrypted by Certificate, Encrypted not by new cert already
 ----------------------------------------------------------------------------------*/
IF OBJECT_ID('tempdb..#DbEncrypted') IS NOT NULL
BEGIN
    DROP TABLE #DbEncrypted
END
CREATE TABLE #DbEncrypted
(
	ServerName NVARCHAR(128),
	DatabaseName NVARCHAR(128),
	CertificateName NVARCHAR(128),
	EncryptorType NVARCHAR(128),
	EncryptionState INT,
	EncryptionStateDesc NVARCHAR(128)
)
INSERT INTO #DbEncrypted
(
    ServerName,
    DatabaseName,
    CertificateName,
    EncryptorType,
    EncryptionState,
    EncryptionStateDesc
)
SELECT 
	@@SERVERNAME as ServerName,
	d.[name] AS DatabaseName,
	c.[name] AS CertificateName,
	e.encryptor_type AS EncryptorType,
	e.encryption_state AS EncryptionState,
	CASE WHEN e.encryption_state = 3 THEN 'Encrypted'
		 WHEN e.encryption_state = 2 THEN 'In Progress'
		 ELSE 'Not Encrypted'
		 END AS EncryptionStateDesc
	--,'USE ' + QUOTENAME(d.[name]) + ';' + 'ALTER DATABASE ENCRYPTION KEY ENCRYPTION BY SERVER CERTIFICATE ' + QUOTENAME(@CertName) +';' AS ChangeEncryptionKeyCommand
FROM sys.dm_database_encryption_keys e
right join sys.databases d on d.database_id = e.database_id
left join sys.certificates c ON e.encryptor_thumbprint=c.thumbprint
WHERE e.encryption_state = 3  --Is Encrypted
AND e.encryptor_type = 'CERTIFICATE'  --Is Encrypted by Certificate
AND c.[name] <> @CertName  --Not already encrypted by new Certificate
ORDER by d.[name]

DECLARE @DatabaseName NVARCHAR(128)
	SELECT TOP(1) @DatabaseName = DatabaseName 
	FROM #DbEncrypted
	ORDER BY DatabaseName

WHILE EXISTS (SELECT 1 FROM #DbEncrypted)
BEGIN
	
	SET @AlterDbEncryptionKeySQL =
	N'USE ' + QUOTENAME(@DatabaseName) +'; ' + CHAR(13) + CHAR(10) 
	+ N'ALTER DATABASE ENCRYPTION KEY ENCRYPTION BY SERVER CERTIFICATE ' + QUOTENAME(@CertName) +';'

	SELECT '--Change the Encryption Cert for the database'
	UNION 
	SELECT @AlterDbEncryptionKeySQL AS AlterEncryptionKey

	DELETE FROM #DbEncrypted WHERE DatabaseName= @DatabaseName

	SELECT TOP(1) @DatabaseName = DatabaseName 
	FROM #DbEncrypted
	ORDER BY DatabaseName

END
