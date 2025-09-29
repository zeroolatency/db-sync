# Manual PostgreSQL Dump & Restore Commands

### Create Dump
```bash
docker exec <postgres-instance-name> pg_dump -U postgres -d source_db > source_database_dump.sql
```

### Restore to Target
```bash
psql -U postgres -d target_db < source_database_dump.sql
```

## Cron Setup
```bash
# Source VM (Every 15 minutes - WAL-based incremental)
*/15 * * * * /usr/local/bin/source_vm_wal_dump_script.sh

# Target VM (Every 5 minutes)
*/5 * * * * /usr/local/bin/target_vm_wal_restore_script.sh
```