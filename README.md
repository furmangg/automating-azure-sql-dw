# Automating Azure SQL DW - Code Samples
My Ignite 2018 presentation entitled [Automating Azure SQL Data Warehouse](https://myignite.techcommunity.microsoft.com/sessions/66195?source=sessions) on September 26, 2018 included demos of various ways to automate Azure SQL DW. These code samples are included here.

### [ADFv2](https://github.com/furmangg/automating-azure-sql-dw/tree/master/ADFv2)

#### BackupAzureSQLDW

The [ADFv2/BackupAzureSQLDW.json](https://raw.githubusercontent.com/furmangg/automating-azure-sql-dw/master/ADFv2/BackupAzureSQLDW.json) file contains an Azure Data Factory v2 pipeline which triggers a backup of your Azure SQL DW. In proper terms, this pipeline creates a [user-defined restore point](https://docs.microsoft.com/en-us/azure/sql-data-warehouse/backup-and-restore#user-defined-restore-points) in your DW. If you DW is paused through the day except for a few hours during the loads then it may not be online long enough to get an automatic restore point created. Furthermore, automatic restore points may happen in the middle of a load making them useless for a restore. Triggering a user-defined restore point ensures you backup the DW at a consistent point before or after a load.

Set the following parameters upon execution of the pipeline:
* **SubscriptionID** - The GUID identifier for the subscription the Azure SQL DW is running from. To get this ID, go to the Subscriptions tab of the Azure Portal.
* **ResourceGroup** - The name of the resource group where the Azure SQL DW lives.
* **Server** - The name of your Azure SQL DW server. This is not the full _yourdwserver.database.windows.net_ server name. This is just the initial _yourdwserver_ section.
* **DW** - The name of the DW database.

This pipeline executes the command under your ADF Managed Service Identity (MSI). Thus that MSI must be granted proper permissions. If your data factory is named "gregadfv2" then go to the Access Control (IAM) tab in the Azure SQL Server's blade, click Add, choose Role=Contributor, then search for your data factory's name, select the MSI that is returned from the search and click Save:

![Assigning MSI permissions](images/ADFMSI.png)


#### PauseAzureSQLDW

The [ADFv2/PauseAzureSQLDW.json](https://raw.githubusercontent.com/furmangg/automating-azure-sql-dw/master/ADFv2/PauseAzureSQLDW.json) file contains an Azure Data Factory v2 pipeline which pauses your DW and loops until the pause is complete. This pipeline immediately pauses your DW without checking whether any queries or loads are running.

Set the following parameters upon execution of the pipeline:
* **SubscriptionID** - The GUID identifier for the subscription the Azure SQL DW is running from. To get this ID, go to the Subscriptions tab of the Azure Portal.
* **ResourceGroup** - The name of the resource group where the Azure SQL DW lives.
* **Server** - The name of your Azure SQL DW server. This is not the full _yourdwserver.database.windows.net_ server name. This is just the initial _yourdwserver_ section.
* **DW** - The name of the DW database.

This pipeline executes the command under your ADF Managed Service Identity (MSI). Thus that MSI must be granted proper permissions as explained in the instructions for BackupAzureSQLDW above.


#### ResumeAzureSQLDW

The [ADFv2/ResumeAzureSQLDW.json](https://raw.githubusercontent.com/furmangg/automating-azure-sql-dw/master/ADFv2/ResumeAzureSQLDW.json) file contains an Azure Data Factory v2 pipeline which resumes (unpauses) your DW and loops until the DW is online. If the DW is already online then it does nothing.

Set the following parameters upon execution of the pipeline:
* **SubscriptionID** - The GUID identifier for the subscription the Azure SQL DW is running from. To get this ID, go to the Subscriptions tab of the Azure Portal.
* **ResourceGroup** - The name of the resource group where the Azure SQL DW lives.
* **Server** - The name of your Azure SQL DW server. This is not the full _yourdwserver.database.windows.net_ server name. This is just the initial _yourdwserver_ section.
* **DW** - The name of the DW database.

This pipeline executes the command under your ADF Managed Service Identity (MSI). Thus that MSI must be granted proper permissions as explained in the instructions for BackupAzureSQLDW above.

<br/><br/>

### [CLI](https://github.com/furmangg/automating-azure-sql-dw/tree/master/CLI)

#### resumeDW.bat

The [CLI/resumeDW.bat](https://raw.githubusercontent.com/furmangg/automating-azure-sql-dw/master/CLI/resumeDW.bat) file is a batch script which calls the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) to resume (unpause) your DW and loop until the DW is online. If the DW is already online then it does nothing.

The script as written is designed to run from within an Azure VM where the Managed Service Identity (MSI) has been [enabled](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-portal-windows-vm) and [granted](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/howto-assign-access-portal) Contributor permissions to the Azure SQL Server.

<br/><br/>

### [Azure Automation](https://github.com/furmangg/automating-azure-sql-dw/tree/master/AzureAutomation)

#### RotateKeys.ps1

The [AzureAutomation/RotateKeys.ps1](https://raw.githubusercontent.com/furmangg/automating-azure-sql-dw/master/AzureAutomation/RotateKeys.ps1) script is designed to keep your Azure SQL DW environment as secure as possible. In case an employee leaves who knows the SQL DW admin password or the blob storage key, key rotation will reset these sensitive passwords and secrets. This script performs the following tasks:

1. Authenticates with the Azure Automation RunAs account
2. Ensures that RunAs account has Azure Key Vault access
3. Starts the DW if it is paused
4. Starts your Azure Analysis Services if it was paused
5. Looks up the current public IP address of the current Azure Automation instance. It then temporarily opens the Azure SQL DW and Azure AS firewall to that IP so that the Azure Automation runbook is able to perform the necessary operations.
6. Rotates the Azure storage account key and then updates this in Azure Key Vault and in the Polybase database scoped credential in Azure SQL DW.
7. Connects to Azure SQL DW with the admin account and changes the password of the admin, AdfLoader and CubeReadOnly SQL accounts
8. Updates Azure Key Vault with the connection string Azure Data Factory uses
9. Updates Azure Key Vault with the CubeReadOnly password so that cube developers can lookup the latest password.
10. Updates Azure Key Vault with the Azure SQL DW admin SQL password so that key rotation next week can look it up.
11. Connect to Azure Analysis Services and loop through all the databases fixing the connection strings in the data sources. (Currently it assumes all data sources connect to Azure SQL DW, so this code may need to be tweaked for your environment.)
12. Resets the Azure SQL DW and Azure Analysis Services firewall to remove the temporary Azure Automation IP address.
13. Pauses Azure SQL DW if Azure Automation started it during key rotation.
14. Pauses Azure Analysis Services if Azure Automation started it during key rotation.

Deploying this solution requires a number of steps:

1. In your Azure Automation account, import the AzureRM.profile, AzureRM.AnalysisServices, AzureRM.KeyVault, and PackageManagement.
1. Ensure the RunAs account is created and is a Contributor on the subscription (or at least the resource groups for Azure Key Vault, Azure SQL DW, Azure Analysis Services and Azure Blob Storage.)
1. Create an Azure Key Vault and grant your ADF Managed Service Identity (MSI) permission to get secrets. (Azure Automation will grant its RunAs account permission to Azure Key Vault secrets.) Grant cube developers or other developers permissions to get secrets.
1. Create a new secret called "dw-admin-password" and populate it with the SQL DW admin password.
1. Create a new secret called "dw-AdfLoader-connectionstring" and populate it with a placeholder like the letter "x". The runbook will set this after key rotation runs the first time.
1. Create a new secret called "dw-CubeReadOnly-password" and populate it with a placeholder like the letter "x". The runbook will set this after key rotation.
1. Create a new secret called "storage-connection-string" and populate it with a placeholder like the letter "x". The runbook will set this after key rotation.
1. Create a new SQL DW login called AdfLoader with db_owner permissions and then update the &lt;YourSqlDwLoginUsedInAdf&gt; token in the PowerShell script with its name.
1. Create a new SQL DW login called CubeReadOnly with db_datareader permissions and then update the &lt;YourSqlDwLoginForAzureAS&gt; token in the PowerShell script with its name.
1. Update the &lt;YourSqlDwAdminUsername&gt; token in the PowerShell script with the name of your SQL DW admin account.
1. Create a new database scoped credential in Azure SQL DW called "credStorage" pointing at the Azure Blob Storage account. Create any additional Polybase objects like external data sources that reference that credential.
1. Connect to Azure Analysis Services in SSMS and right click on the server node and choose Properties and on the Security tab. Click Add to add a new admin user. Search for the name of your Azure Automation Account in order to find the RunAs account and add this identity.
1. Deploy your Azure Analysis Services model using the CubeReadOnly account.
1. Create a new lsAzureKeyVault linked service in Azure Data Factory pointing to Azure Key Vault.
1. Create a new linked service in Azure Data Factory pointing to Azure SQL DW but have it get the connection string from the "dw-AdfLoader-connectionstring" secret in lsAzureKeyVault.
1. Create a new linked service in Azure Data Factory pointing to Azure Blob Storage but have it get the connection string from the "storage-connection-string" secret in lsAzureKeyVault.
1. In the Azure Automation pane for the RotateKeys runbook click the Schedule button, setup a schedule such as every Sunday morning, then set the parameters as follows.

The runbook has the following parameters:
* **StorageAccountName** - The name of your storage account which will have its keys rotated, the new key updated in Azure SQL DW in the database scoped credential, and the key updated in the Azure Key Vault secret which Azure Automation uses.
* **StorageAccountResourceGroupName** - The name of the resource group where your storage account lives.
* **VaultName** - The name of your Azure Key Vault.
* **SqlDwServerName** - The name of your Azure SQL DW server. This is not the full _yourdwserver.database.windows.net_ server name. This is just the initial _yourdwserver_ section.
* **SqlDwDatabaseName** - The name of the DW database.
* **SqlDwResourceGroupName** - The name of the resource group where your DW lives.
* **AzureASServer** - The name of your Azure Analysis Services. This is not the full asazure:// URI. This is just the final section saying the name of your server.
* **AzureASResourceGroupName** - The name of the resource group where your Azure Analysis Services lives.

<br/><br/>

### Questions or Issues

Use the [Issues](https://github.com/furmangg/automating-azure-sql-dw/issues) tab to report bugs or post questions. Better yet, fix the problem yourself and propose changes...


### Proposing Changes

Enhancements to code or documentation are welcome. Create a pull request.

<br/><br/>
