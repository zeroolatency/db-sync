#!/bin/bash

TARGET_DB_HOST="localhost"
TARGET_DB_PORT="5434"
TARGET_DB_NAME="target_db"
TARGET_DB_USER="postgres"
DUMP_DIR="/var/backups/postgres"
LOG_FILE="/var/log/postgres_restore.log"
LOCK_FILE="/var/run/postgres_restore.lock"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

if [ -f $LOCK_FILE ]; then
    log_message "WARNING: Restore process already running, skipping"
    exit 0
fi

touch $LOCK_FILE

cleanup() {
    rm -f $LOCK_FILE
}
trap cleanup EXIT

mkdir -p $DUMP_DIR

log_message "Starting database restore monitoring"

if ! pg_isready -h $TARGET_DB_HOST -p $TARGET_DB_PORT -U $TARGET_DB_USER; then
    log_message "ERROR: PostgreSQL is not running on target host"
    exit 1
fi

if [ ! -f "${DUMP_DIR}/dump_ready.flag" ]; then
    log_message "No new dump available, exiting"
    exit 0
fi

LATEST_DUMP=$(ls -t ${DUMP_DIR}/source_db_*.sql.gz 2>/dev/null | head -n1)

if [ -z "$LATEST_DUMP" ]; then
    log_message "ERROR: No dump files found"
    exit 1
fi

log_message "Found latest dump: $LATEST_DUMP"

PROCESSED_FILE="${LATEST_DUMP}.processed"
if [ -f "$PROCESSED_FILE" ]; then
    log_message "Dump already processed, exiting"
    exit 0
fi

BACKUP_FILE="${DUMP_DIR}/backup_before_restore_$(date +%Y%m%d_%H%M%S).sql"
log_message "Creating backup before restore: $BACKUP_FILE"
pg_dump -h $TARGET_DB_HOST -p $TARGET_DB_PORT -U $TARGET_DB_USER -d $TARGET_DB_NAME > $BACKUP_FILE

if [ $? -eq 0 ]; then
    log_message "Backup created successfully"
else
    log_message "WARNING: Backup creation failed, proceeding with restore"
fi

log_message "Starting restore process from: $LATEST_DUMP"

gunzip -c $LATEST_DUMP | psql -h $TARGET_DB_HOST -p $TARGET_DB_PORT -U $TARGET_DB_USER -d $TARGET_DB_NAME

if [ $? -eq 0 ]; then
    log_message "SUCCESS: Database restored successfully"
    
    touch $PROCESSED_FILE
    log_message "Marked dump as processed: $PROCESSED_FILE"
    
    rm -f "${DUMP_DIR}/dump_ready.flag"
    log_message "Removed dump ready flag"
    
    USER_COUNT=$(psql -h $TARGET_DB_HOST -p $TARGET_DB_PORT -U $TARGET_DB_USER -d $TARGET_DB_NAME -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ')
    ORDER_COUNT=$(psql -h $TARGET_DB_HOST -p $TARGET_DB_PORT -U $TARGET_DB_USER -d $TARGET_DB_NAME -t -c "SELECT COUNT(*) FROM orders;" 2>/dev/null | tr -d ' ')
    
    log_message "Data verification - Users: $USER_COUNT, Orders: $ORDER_COUNT"
    
    ls -t ${DUMP_DIR}/source_db_*.sql.gz.processed 2>/dev/null | tail -n +11 | xargs -r rm -f
    log_message "Cleaned up old processed dump files"
    
else
    log_message "ERROR: Database restore failed"
    
    if [ -f "$BACKUP_FILE" ]; then
        log_message "Attempting to restore from backup: $BACKUP_FILE"
        psql -h $TARGET_DB_HOST -p $TARGET_DB_PORT -U $TARGET_DB_USER -d $TARGET_DB_NAME < $BACKUP_FILE
        
        if [ $? -eq 0 ]; then
            log_message "SUCCESS: Restored from backup"
        else
            log_message "ERROR: Backup restore also failed"
        fi
    fi
    
    exit 1
fi

log_message "Database restore process completed successfully"
