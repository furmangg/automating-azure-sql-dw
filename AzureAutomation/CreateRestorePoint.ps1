param(

	[Parameter(Mandatory=$true)]
    [string] $SqlDwServerName,

	[Parameter(Mandatory=$true)]
    [string] $SqlDwDatabaseName,

	[Parameter(Mandatory=$true)]
    [string] $SqlDwResourceGroupName

)



try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}



$Date=Get-Date 
$Label = $SqlDwDatabaseName + "_Backup_" + $Date

New-AzSqlDatabaseRestorePoint -ResourceGroupName $SqlDwResourceGroupName -ServerName $SqlDwServerName -DatabaseName $SqlDwDatabaseName -RestorePointLabel $Label

"Successfully created a User Defined Restore Point $Label"


