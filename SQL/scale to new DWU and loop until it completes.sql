--author: Greg Galloway
--from: https://github.com/furmangg/automating-azure-sql-dw

--to allow a user to scale the DW using ALTER DATABASE then you need this permission in master
--ALTER ROLE dbmanager ADD MEMBER [UserNameHere];
--run this against master
declare @DWU varchar(20) = 'DW200c';

--either set this to specific value or just assume there's only one DW on this server
declare @db varchar(255);
SELECT @db = db.[name]
FROM
 sys.database_service_objectives ds
 JOIN sys.databases db ON ds.database_id = db.database_id
where ds.edition = 'DataWarehouse';

declare @sql varchar(8000) = 'ALTER DATABASE ' + @db
+ ' MODIFY (SERVICE_OBJECTIVE = ''' + @DWU + ''')';
print 'starting executing ALTER DATABASE for ' + @db + ': ' + convert(varchar,getdate(),120);
exec(@sql)
print 'done executing ALTER DATABASE: ' + convert(varchar,getdate(),120);

waitfor delay '00:00:02';

--PENDING = operation is waiting for resource or quota availability.
--IN_PROGRESS = operation has started and is in progress.
--COMPLETED = operation completed successfully.
--FAILED = operation failed. See the error_desc column for details.
--CANCELLED = operation stopped at the request of the user.
while (
	select top 1 state_desc
	from sys.dm_operation_status 
	WHERE resource_type_desc = 'Database'
	AND major_resource_id = @db
	AND operation = 'ALTER DATABASE' 
	order by start_time desc
) not in ('COMPLETED','FAILED','CANCELLED')
begin
	print 'waiting for scaling to complete: ' + convert(varchar,getdate(),120);
	waitfor delay '00:00:30';
end

declare @status nvarchar(120);
declare @error_desc nvarchar(2048);
select top 1 @status = state_desc, @error_desc = error_desc
from sys.dm_operation_status 
WHERE resource_type_desc = 'Database'
AND major_resource_id = @db
AND operation = 'ALTER DATABASE' 
order by start_time desc;

if @status in ('FAILED','CANCELLED')
begin
	declare @errmsg nvarchar(2048) = 'Scaling did NOT succeed. Status=' + @status + '; Error=' + @error_desc;
	THROW 51000, @errmsg, 20;  
end

print 'scaling complete!';

--wait! need to wait another minute as a subsequent statement will often fail
waitfor delay '00:01:00';
