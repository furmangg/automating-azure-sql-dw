param(
	[Parameter(Mandatory=$true)]
    [string] $StorageAccountName,
	
	[Parameter(Mandatory=$true)]
    [string] $StorageAccountResourceGroupName,
	
	[Parameter(Mandatory=$true)]
    [string] $VaultName,

	[Parameter(Mandatory=$true)]
    [string] $SqlDwServerName,

	[Parameter(Mandatory=$true)]
    [string] $SqlDwDatabaseName,

	[Parameter(Mandatory=$true)]
    [string] $SqlDwResourceGroupName,

	[Parameter(Mandatory=$true)]
    [string] $AzureASServer,

	[Parameter(Mandatory=$true)]
    [string] $AzureASResourceGroupName
)


#hardcoded variables that don't change from dev to prod
$StorageConnectionStringSecret = "storage-connection-string"

$SqlDwAdminUsername = "<YourSqlDwAdminUsername>"
$SqlDwAdminPasswordSecret = "dw-admin-password"

$SqlDwAdfConnectionStringSecret = "dw-AdfLoader-connectionstring"
$SqlDwAdfLoaderUsername = "<YourSqlDwLoginUsedInAdf>"

$SqlDwCubeReadOnlyUsername = "<YourSqlDwLoginForAzureAS>"
$SqlDwCubeReadOnlyPasswordSecret = "dw-CubeReadOnly-password"

$SqlDwDatabaseScopedCredentialName = "credStorage"


$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    $login = Connect-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
    "Login complete."
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

"Rotating keys for the following systems:"
"Azure SQL DW server $SqlDwServerName database $SqlDwDatabaseName"
"Azure Blob Storage account $StorageAccountName"
"Azure Key Vault $VaultName"

Set-AzureRmKeyVaultAccessPolicy -VaultName $VaultName -ServicePrincipalName $servicePrincipalConnection.ApplicationId -PermissionsToSecrets Get,Set;
"Successfully ensured Azure Automation has Azure Key Vault access"


$status = Get-AzureRmSqlDatabase –ResourceGroupName $SqlDwResourceGroupName –ServerName $SqlDwServerName -DatabaseName $SqlDwDatabaseName | Select Status
"Azure SQL DW state: " + $status.Status;

# Check the status
if($status.Status -eq "Paused")
{
    $sqldw = Resume-AzureRmSqlDatabase –ResourceGroupName $SqlDwResourceGroupName –ServerName $SqlDwServerName –DatabaseName $SqlDwDatabaseName  
    $mustPauseAzureSQLDW = $true;
    "Successfully Resumed SQL DW"
} 
else 
{
    $mustPauseAzureSQLDW = $false;
}


$asServer = Get-AzureRmAnalysisServicesServer -ResourceGroupName $AzureASResourceGroupName -Name $AzureASServer
[string]$AzureAsServerFullName = $asServer.ServerFullName;

"Current Azure AS status: $($asServer.State)"

if ($asServer.State -ne "Succeeded")
{
    $null = ($asServer | Resume-AzureRmAnalysisServicesServer -Verbose)
    "Successfully Resumed Azure AS"
    $mustPauseAzureAS = $true;
}
else
{
    $mustPauseAzureAS = $false;
}


$ipinfo = Invoke-RestMethod http://ipinfo.io/json 

if ($asServer.FirewallConfig -ne $null)
{
    for ($i = 0; $i -lt $asServer.FirewallConfig.FirewallRules.Count; $i++)
    {
        $rule = $asServer.FirewallConfig.FirewallRules[$i];
        if ($rule.FirewallRuleName -eq "AzureAutomation")
        {
            $asServer.FirewallConfig.FirewallRules.Remove($rule);
            $i--;
        }
    }

    #backup the firewall rules
    $rulesBackup = $asServer.FirewallConfig.FirewallRules.ToArray()

    #add a new AzureAutomation firewall rule
    $newRule = New-AzureRmAnalysisServicesFirewallRule -FirewallRuleName "AzureAutomation" -RangeStart $ipinfo.ip  -RangeEnd $ipinfo.ip
    $asServer.FirewallConfig.FirewallRules.Add($newRule)
    Set-AzureRmAnalysisServicesServer -ResourceGroupName $AzureASResourceGroupName -Name $AzureASServer -FirewallConfig $asServer.FirewallConfig

    "Updated Azure AS firewall to allow current Azure Automation Public IP: " + $ipinfo.ip
}
else
{
    "Azure AS Firewall is off"
}


#if the Azure SQL firewall does NOT allow connections from Azure
if (-Not (Get-AzureRmSqlServerFirewallRule -ResourceGroupName $SqlDwResourceGroupName -ServerName $SqlDwServerName | Where-Object { $_.StartIpAddress -eq "0.0.0.0" }))
{
    if (Get-AzureRmSqlServerFirewallRule -ResourceGroupName $SqlDwResourceGroupName -ServerName $SqlDwServerName -FirewallRuleName "AzureAutomation" -ErrorAction Ignore)
    {
        Set-AzureRmSqlServerFirewallRule -FirewallRuleName "AzureAutomation" -StartIpAddress $ipinfo.ip -EndIpAddress $ipinfo.ip -ResourceGroupName $SqlDwResourceGroupName -ServerName $SqlDwServerName;
    }
    else
    {
        New-AzureRmSqlServerFirewallRule -FirewallRuleName "AzureAutomation" -StartIpAddress $ipinfo.ip -EndIpAddress $ipinfo.ip -ResourceGroupName $SqlDwResourceGroupName -ServerName $SqlDwServerName;
    }
    "Updated Azure SQL DW firewall to allow current Azure Automation Public IP: " + $ipinfo.ip
}
else
{
    "Azure SQL DW Firewall allows Azure to connect"
}



function InstallAndLoadTOM {
    $null = Register-PackageSource -Name nuget.org -Location http://www.nuget.org/api/v2 -Force -Trusted -ProviderName NuGet;
    $install = Install-Package Microsoft.AnalysisServices.retail.amd64 -ProviderName NuGet;
    if ($install.Payload.Directories -ne $null)
    {
        $dllFolder = $install.Payload.Directories[0].Location + "\" + $install.Payload.Directories[0].Name + "\lib\net45\"
        Add-Type -Path ($dllFolder + "Microsoft.AnalysisServices.Core.dll")
        Add-Type -Path ($dllFolder + "Microsoft.AnalysisServices.Tabular.Json.dll")
        Add-Type -Path ($dllFolder + "Microsoft.AnalysisServices.Tabular.dll")
        $amoAzureASServer = New-Object -TypeName Microsoft.AnalysisServices.Tabular.Server 
        "Loaded Tabular Object Model assemblies"
    }
}


#passing in $keyIndex=0 changes key1
#passing in $keyIndex=1 changes key2
function RotateStorageAccountKey([int]$keyIndex)
{
    [string]$keyName = "key" + ($keyIndex+1)

    #rotate the key in blob storage
    $SAKeys = New-AzureRmStorageAccountKey -ResourceGroupName $StorageAccountResourceGroupName -Name $StorageAccountName -KeyName $keyName -Verbose
    $storageAccountKey = $SAKeys.Keys[$keyIndex].Value;
    $storageConnectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=" + $storageAccountKey;

    "Successfully rotated blob storage $keyName"

    $secretvalue = ConvertTo-SecureString $storageConnectionString -AsPlainText -Force
    $secret = Set-AzureKeyVaultSecret -VaultName $VaultName -Name $StorageConnectionStringSecret -SecretValue $secretvalue

    "Successfully updated Azure Key Vault secret $StorageConnectionStringSecret"

    $secret = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SqlDwAdminPasswordSecret
    $SqlDwAdminPassword = $secret.SecretValueText
        
    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = 'Data Source=' + $SqlDwServerName + '.database.windows.net;Initial Catalog=' + $SqlDwDatabaseName + ';Integrated Security=False;User ID=' + $SqlDwAdminUsername + ';Password=' + $SqlDwAdminPassword + ';Connect Timeout=60;Encrypt=False;TrustServerCertificate=False;'
    $conn.Open()

    $cmd = New-Object System.Data.SqlClient.SqlCommand
    $cmd.Connection = $conn
    $cmd.CommandText = "ALTER DATABASE SCOPED CREDENTIAL $SqlDwDatabaseScopedCredentialName WITH IDENTITY = 'blob',  SECRET = '$storageAccountKey';"
    $queryOutput = $cmd.ExecuteNonQuery();

    "Successfully updated Azure SQL DW database scoped credential $SqlDwDatabaseScopedCredentialName with storage account key"
}


#rotate key 2 (index 1) then key 1 (index 0)
RotateStorageAccountKey(1)
RotateStorageAccountKey(0)


function GetNewPassword
{
    return (([char[]]((New-Guid).ToString() + '*%#!/ABCDEF')) | sort {Get-Random}) -join ''
}


$secret = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SqlDwAdminPasswordSecret
$SqlDwAdminPassword = $secret.SecretValueText

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = 'Data Source=' + $SqlDwServerName + '.database.windows.net;Initial Catalog=master;Integrated Security=False;User ID=' + $SqlDwAdminUsername + ';Password=' + $SqlDwAdminPassword + ';Connect Timeout=60;Encrypt=False;TrustServerCertificate=False;'
$conn.Open()

#generate a new SQL DW AdfLoader password
$NewSqlDwAdfLoaderPassword = GetNewPassword;

$cmd = New-Object System.Data.SqlClient.SqlCommand
$cmd.Connection = $conn
$cmd.CommandText = "ALTER LOGIN $SqlDwAdfLoaderUsername WITH PASSWORD = '$NewSqlDwAdfLoaderPassword';"
$queryOutput = $cmd.ExecuteNonQuery();
"Successfully updated password for $SqlDwAdfLoaderUsername login"

$NewSqlDwAdfConnectionString = 'Server=tcp:' + $SqlDwServerName + '.database.windows.net,1433;Database=' + $SqlDwDatabaseName + ';User ID=' + $SqlDwAdfLoaderUsername + ';Password=' + $NewSqlDwAdfLoaderPassword + ';Trusted_Connection=False;Encrypt=True;Connection Timeout=60'

$secretvalue = ConvertTo-SecureString $NewSqlDwAdfConnectionString -AsPlainText -Force
$secret = Set-AzureKeyVaultSecret -VaultName $VaultName -Name $SqlDwAdfConnectionStringSecret -SecretValue $secretvalue
"Successfully updated Azure Key Vault secret $SqlDwAdfConnectionStringSecret"


#generate a new SQL DW CubeReadOnly password
$NewSqlDwCubeReadOnlyPassword = GetNewPassword;

$cmd = New-Object System.Data.SqlClient.SqlCommand
$cmd.Connection = $conn
$cmd.CommandText = "ALTER LOGIN $SqlDwCubeReadOnlyUsername WITH PASSWORD = '$NewSqlDwCubeReadOnlyPassword';"
$queryOutput = $cmd.ExecuteNonQuery();
"Successfully updated password for $SqlDwCubeReadOnlyUsername login"

$secretvalue = ConvertTo-SecureString $NewSqlDwCubeReadOnlyPassword -AsPlainText -Force
$secret = Set-AzureKeyVaultSecret -VaultName $VaultName -Name $SqlDwCubeReadOnlyPasswordSecret -SecretValue $secretvalue
"Successfully updated Azure Key Vault secret $SqlDwCubeReadOnlyPasswordSecret"

InstallAndLoadTOM

        
$amoAzureASServer = New-Object -TypeName Microsoft.AnalysisServices.Tabular.Server 
$amoAzureASServer.Connect("Data Source=$AzureAsServerFullName;User ID=app:" + $servicePrincipalConnection.ApplicationId + "@" + $servicePrincipalConnection.TenantId + ";Provider=MSOLAP;Persist Security Info=True;Impersonation Level=Impersonate;Password=cert:" + $servicePrincipalConnection.CertificateThumbprint)
if ($amoAzureASServer.Databases.Count -eq 0)
{
    "Warning: No Azure AS databases found! Ensure app:" + $servicePrincipalConnection.ApplicationId + "@" + $servicePrincipalConnection.TenantId + " has Analysis Server Admin access"
}
$amoAzureASServer.Databases | ForEach-Object {
    $db = $_;
    "Finding data sources in Azure AS database " + $db.Name
    $madeChange = $false;
    $db.Model.DataSources | ForEach-Object {
        $ds = $_;
        if ($ds.GetType().Name -eq "ProviderDataSource")
        {
            if ($ds.Provider -eq "System.Data.SqlClient")
            {
                $ds.ImpersonationMode = [Microsoft.AnalysisServices.Tabular.ImpersonationMode]::ImpersonateServiceAccount; #developers may have had to deploy with the ImpersonateAccount setting because they aren't server admins
                $ds.Account = "";
                $ds.Password = "";
                $ds.ConnectionString = "x";
                $connStr = "Data Source=tcp:$SqlDwServerName.database.windows.net,1433;Initial Catalog=$SqlDwDatabaseName;User ID=$SqlDwCubeReadOnlyUsername;Password=$NewSqlDwCubeReadOnlyPassword;Persist Security Info=true;Encrypt=true;TrustServerCertificate=false;Packet Size=32767;"
                $tmsl = [Microsoft.AnalysisServices.Tabular.JsonScripter]::ScriptAlter($ds);
                $tmsl = $tmsl.Replace("********",$connStr);
                #would normally do $db.Model.SaveChanges() but was getting an error so used this as a workaround
                $results = $amoAzureASServer.Execute($tmsl);

                foreach ($message in $results.Messages)
                {
                    if ($message.GetType().FullName -eq "Microsoft.AnalysisServices.XmlaError")
                    {
                        throw $message.Description
                    }
                    if ($message.GetType().FullName -eq "Microsoft.AnalysisServices.XmlaWarning")
                    {
                        "Warning $($message.Description)"
                    }
                }
                "Updated connection string in data source: " + $ds.Name
            }
            elseif ($ds.Provider -eq "")
            {
                $ds.ImpersonationMode = [Microsoft.AnalysisServices.Tabular.ImpersonationMode]::ImpersonateServiceAccount; #developers may have had to deploy with the ImpersonateAccount setting because they aren't server admins
                $ds.Account = "";
                $ds.Password = "";
                $ds.ConnectionString = "x";
                $connStr = "Provider=SQLNCLI11;Data Source=tcp:$SqlDwServerName.database.windows.net,1433;Initial Catalog=$SqlDwDatabaseName;User ID=$SqlDwCubeReadOnlyUsername;Password=$NewSqlDwCubeReadOnlyPassword;Persist Security Info=true;Packet Size=32767;"
                $tmsl = [Microsoft.AnalysisServices.Tabular.JsonScripter]::ScriptAlter($ds);
                $tmsl = $tmsl.Replace("********",$connStr);
                #would normally do $db.Model.SaveChanges() but was getting an error so used this as a workaround
                $results = $amoAzureASServer.Execute($tmsl);

                foreach ($message in $results.Messages)
                {
                    if ($message.GetType().FullName -eq "Microsoft.AnalysisServices.XmlaError")
                    {
                        throw $message.Description
                    }
                    if ($message.GetType().FullName -eq "Microsoft.AnalysisServices.XmlaWarning")
                    {
                        "Warning $($message.Description)"
                    }
                }
                "Updated connection string in data source: " + $ds.Name
            }
            else
            {
                "Unsupported data source: " + $ds.Name
            }
        } 
        else 
        {
            $ds.Credential.AuthenticationKind = "UsernamePassword";
            $ds.Credential.Username = $SqlDwCubeReadOnlyUsername;
            $ds.Credential.Password = "x";
            $ds.Credential.EncryptConnection = $true;
            $tmsl = [Microsoft.AnalysisServices.Tabular.JsonScripter]::ScriptAlter($ds);
            $tmsl = $tmsl.Replace("********",$NewSqlDwCubeReadOnlyPassword);

            #would normally do $db.Model.SaveChanges() but was getting an error so used this as a workaround
            $results = $amoAzureASServer.Execute($tmsl);

            foreach ($message in $results.Messages)
            {
                if ($message.GetType().FullName -eq "Microsoft.AnalysisServices.XmlaError")
                {
                    throw $message.Description
                }
                if ($message.GetType().FullName -eq "Microsoft.AnalysisServices.XmlaWarning")
                {
                    "Warning $($message.Description)"
                }
            }

            "Updated credentials in modern data source: " + $ds.Name
        }
    }
}
$null = $amoAzureASServer.Disconnect();


#generate a new SQL DW admin password
$NewSqlDwAdminPassword = GetNewPassword;

$cmd.CommandText = "ALTER LOGIN $SqlDwAdminUsername WITH PASSWORD = '$NewSqlDwAdminPassword';"
$queryOutput = $cmd.ExecuteNonQuery();
"Successfully updated password for $SqlDwAdminUsername login"

$secretvalue = ConvertTo-SecureString $NewSqlDwAdminPassword -AsPlainText -Force
$secret = Set-AzureKeyVaultSecret -VaultName $VaultName -Name $SqlDwAdminPasswordSecret -SecretValue $secretvalue
"Successfully updated Azure Key Vault secret $SqlDwAdminPasswordSecret"


if (Get-AzureRmSqlServerFirewallRule -ResourceGroupName $SqlDwResourceGroupName -ServerName $SqlDwServerName -FirewallRuleName "AzureAutomation" -ErrorAction Ignore)
{
    Remove-AzureRmSqlServerFirewallRule -FirewallRuleName "AzureAutomation" -ResourceGroupName $SqlDwResourceGroupName -ServerName $SqlDwServerName;
    "Reset Azure SQL DW firewall rules"
}


if($mustPauseAzureSQLDW)
{
    $null = Suspend-AzureRmSqlDatabase –ResourceGroupName $SqlDwResourceGroupName –ServerName $SqlDwServerName –DatabaseName $SqlDwDatabaseName  
    "Successfully Paused SQL DW"
} 

 

if ($asServer.FirewallConfig -ne $null)
{
    #reset firewall to the state it was in before this script started
    $asServer.FirewallConfig.FirewallRules.Clear()
    $asServer.FirewallConfig.FirewallRules.AddRange($rulesBackup)
    Set-AzureRmAnalysisServicesServer -ResourceGroupName $AzureASResourceGroupName -Name $AzureASServer -FirewallConfig $asServer.FirewallConfig
    "Reset Azure AS firewall rules"
}


if ($mustPauseAzureAS)
{
    $null = ($asServer | Suspend-AzureRmAnalysisServicesServer -Verbose)
    "Successfully Paused Azure AS"
}

"Successfully completed rotating keys"