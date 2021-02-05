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


# Get old status 
$OldDbSetting = Get-AzureRmSqlDatabase -DatabaseName $SqlDwDatabaseName -ServerName $SqlDwServerName -ResourceGroupName $SqlDwResourceGroupName
$OldStatus = $OldDbSetting.Status



if($OldStatus -eq "Online")
 {
   Write-Output "Database $($SqlDwDatabaseName) already in online state."
 }
 else
 {
    
    $null = Resume-AzureRmSqlDatabase -DatabaseName $SqlDwDatabaseName -ServerName $SqlDwServerName -ResourceGroupName $SqlDwResourceGroupName
    Write-Output "Resumed $($SqlDwDatabaseName) database of $($SqlDwResourceGroupName) resource group."
 }

