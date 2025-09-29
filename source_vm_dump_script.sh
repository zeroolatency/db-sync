#!/bin/bash

SOURCE_DB_HOST="localhost"
SOURCE_DB_PORT="5433"
SOURCE_DB_NAME="source_db"
SOURCE_DB_USER="postgres"
TARGET_VM_HOST="target-vm-ip"
TARGET_VM_USER="postgres"
DUMP_DIR="/var/backups/postgres"
LOG_FILE="/var/log/postgres_dump.log"

mkdir -p $DUMP_DIR

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DUMP_FILE="${DUMP_DIR}/source_db_${TIMESTAMP}.sql"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

log_message "Starting database dump process"

if ! docker ps | grep -q "postgres_instance_1"; then
    log_message "ERROR: PostgreSQL container is not running"
    exit 1
fi

log_message "Creating pg_dump: $DUMP_FILE"
docker exec postgres_instance_1 pg_dump -h $SOURCE_DB_HOST -p $SOURCE_DB_PORT -U $SOURCE_DB_USER -d $SOURCE_DB_NAME > $DUMP_FILE

if [ $? -eq 0 ]; then
    log_message "SUCCESS: pg_dump created successfully"
    
    gzip $DUMP_FILE
    DUMP_FILE="${DUMP_FILE}.gz"
    log_message "Dump file compressed: $DUMP_FILE"
    
    log_message "Transferring dump to target VM: $TARGET_VM_HOST"
    scp -o StrictHostKeyChecking=no $DUMP_FILE $TARGET_VM_USER@$TARGET_VM_HOST:/var/backups/postgres/
    
    if [ $? -eq 0 ]; then
        log_message "SUCCESS: Dump file transferred to target VM"
        
        find $DUMP_DIR -name "source_db_*.sql.gz" -mtime +7 -delete
        log_message "Cleaned up old dump files"
        
        ssh -o StrictHostKeyChecking=no $TARGET_VM_USER@$TARGET_VM_HOST "echo 'NEW_DUMP_READY' > /var/backups/postgres/dump_ready.flag"
        log_message "Notified target VM of new dump"
        
    else
        log_message "ERROR: Failed to transfer dump to target VM"
        exit 1
    fi
else
    log_message "ERROR: pg_dump failed"
    exit 1
fi

log_message "Database dump process completed successfully"