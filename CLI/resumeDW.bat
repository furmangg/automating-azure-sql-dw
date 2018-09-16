REM from within an Azure VM with the Managed Service Identity (MSI) and the MSI having permissions to the Azure SQL Server, use az login --identity
REM otherwise run "az login -h" for other options
REM fill in the <bracketed> parameters below
call az login --identity
call az account set -s <subscription_id>
call az sql dw resume --resource-group <resource_group> --server <server> --name <database>

REM occasionally the resume command completes slightly before the DW is unpaused so loop until status says Online
:checkOnline
call az sql dw show --resource-group <resource_group> --server <server> --name <database> | findstr /C:"\\\"status\\\": \\\"Online\\\""
if not %errorlevel%==0 goto :checkOnline
