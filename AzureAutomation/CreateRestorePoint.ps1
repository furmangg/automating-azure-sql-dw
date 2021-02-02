param(

	[Parameter(Mandatory=$true)]
    [string] $SqlDwServerName,

	[Parameter(Mandatory=$true)]
    [string] $SqlDwDatabaseName,

	[Parameter(Mandatory=$true)]
    [string] $SqlDwResourceGroupName

)



$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
$ErrorActionPreference = "Stop";




$Date=Get-Date 
$Label = $SqlDwDatabaseName + "_Backup_" + $Date

New-AzureRMSqlDatabaseRestorePoint -ResourceGroupName $SqlDwResourceGroupName -ServerName $SqlDwServerName -DatabaseName $SqlDwDatabaseName -RestorePointLabel $Label

"Successfully created a User Defined Restore Point $Label"


