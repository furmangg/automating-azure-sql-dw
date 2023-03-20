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


# Get old status 
$OldDbSetting = Get-AzSqlDatabase -DatabaseName $SqlDwDatabaseName -ServerName $SqlDwServerName -ResourceGroupName $SqlDwResourceGroupName
$OldStatus = $OldDbSetting.Status



if($OldStatus -eq "Online")
 {
   Write-Output "Database $($SqlDwDatabaseName) already in online state."
 }
 else
 {
    
    $null = Resume-AzSqlDatabase -DatabaseName $SqlDwDatabaseName -ServerName $SqlDwServerName -ResourceGroupName $SqlDwResourceGroupName
    Write-Output "Resumed $($SqlDwDatabaseName) database of $($SqlDwResourceGroupName) resource group."
 }

