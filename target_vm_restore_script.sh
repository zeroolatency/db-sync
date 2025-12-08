#!/bin/bash

set -euo pipefail

#============================
# CONFIGURATION
#============================
TARGET_DB_HOST="localhost"
TARGET_DB_PORT="5434"
TARGET_DB_NAME="postgres"      # <-- FIX THIS
TARGET_DB_USER="postgres"
TARGET_DB_PASSWORD="password"

DUMP_DIR="./backups/postgres"
LOG_DIR="./logs"
RUN_DIR="./run"
LOG_FILE="${LOG_DIR}/postgres_restore.log"
LOCK_FILE="${RUN_DIR}/postgres_restore.lock"

# Export password so pg_dump/psql work non-interactively
export PGPASSWORD="$TARGET_DB_PASSWORD"

#============================
# INIT DIRECTORIES
#============================
mkdir -p "$DUMP_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$RUN_DIR"

#============================
# LOGGING
#============================
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

#============================
# LOCKING (prevent duplicates)
#============================
if [ -f "$LOCK_FILE" ]; then
    log_message "WARNING: Restore already running. Exiting."
    exit 0
fi

touch "$LOCK_FILE"

cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

log_message "Starting database restore monitoring"

#============================
# CHECK DB IS AVAILABLE
#============================
if ! pg_isready -h "$TARGET_DB_HOST" -p "$TARGET_DB_PORT" -U "$TARGET_DB_USER" >/dev/null 2>&1; then
    log_message "ERROR: PostgreSQL is not reachable at ${TARGET_DB_HOST}:${TARGET_DB_PORT}"
    exit 1
fi

#============================
# CHECK FOR READY FLAG
#============================
READY_FLAG="${DUMP_DIR}/dump_ready.flag"

if [ ! -f "$READY_FLAG" ]; then
    log_message "No new dump available. Exiting."
    exit 0
fi

#============================
# FIND ALL DUMP FILES WITH SAME TIMESTAMP
#============================
# Get the timestamp from the flag file or find the latest timestamp from dump files
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Find all dump files matching the pattern: DBNAME_TIMESTAMP.sql.gz
DUMP_FILES=$(ls -t "$DUMP_DIR"/*_*.sql.gz 2>/dev/null | grep -E ".*_[0-9]{8}_[0-9]{6}\.sql\.gz$" || true)

if [ -z "$DUMP_FILES" ]; then
    log_message "ERROR: No dump files found matching pattern *_TIMESTAMP.sql.gz"
    exit 1
fi

# Group dumps by timestamp (get the latest timestamp from all files)
LATEST_TIMESTAMP=""
for dump_file in $DUMP_FILES; do
    filename=$(basename "$dump_file" .sql.gz)
    # Extract timestamp (format: DBNAME_YYYYMMDD_HHMMSS)
    file_timestamp=$(echo "$filename" | sed -E 's/.*_([0-9]{8}_[0-9]{6})$/\1/')
    if [ -n "$file_timestamp" ] && [ "$file_timestamp" \> "$LATEST_TIMESTAMP" ]; then
        LATEST_TIMESTAMP="$file_timestamp"
    fi
done

if [ -z "$LATEST_TIMESTAMP" ]; then
    log_message "ERROR: Could not determine timestamp from dump files"
    exit 1
fi

log_message "Found latest dump timestamp: $LATEST_TIMESTAMP"

# Find all dump files with this timestamp
DUMP_FILES_ARRAY=()
for dump_file in $DUMP_FILES; do
    filename=$(basename "$dump_file" .sql.gz)
    file_timestamp=$(echo "$filename" | sed -E 's/.*_([0-9]{8}_[0-9]{6})$/\1/')
    if [ "$file_timestamp" = "$LATEST_TIMESTAMP" ]; then
        DUMP_FILES_ARRAY+=("$dump_file")
    fi
done

if [ ${#DUMP_FILES_ARRAY[@]} -eq 0 ]; then
    log_message "ERROR: No dump files found with timestamp $LATEST_TIMESTAMP"
    exit 1
fi

log_message "Found ${#DUMP_FILES_ARRAY[@]} database dump(s) to restore: ${DUMP_FILES_ARRAY[*]}"

#============================
# CHECK IF ALREADY PROCESSED
#============================
PROCESSED_FLAG="${DUMP_DIR}/restore_${LATEST_TIMESTAMP}.processed"

if [ -f "$PROCESSED_FLAG" ]; then
    log_message "Dumps with timestamp $LATEST_TIMESTAMP already processed. Exiting."
    exit 0
fi

#============================
# BACKUP CURRENT DATABASES
#============================
BACKUP_DIR="${DUMP_DIR}/backups_before_restore_${LATEST_TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

log_message "Creating backups before restore in: $BACKUP_DIR"

# Get list of existing databases to backup
EXISTING_DBS=$(psql -h "$TARGET_DB_HOST" -p "$TARGET_DB_PORT" -U "$TARGET_DB_USER" -d postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';" | tr -d ' ')

BACKUP_COUNT=0
for db_name in $EXISTING_DBS; do
    if [ -n "$db_name" ]; then
        BACKUP_FILE="${BACKUP_DIR}/${db_name}_backup.sql"
        log_message "Backing up database '$db_name'"
        if pg_dump -h "$TARGET_DB_HOST" -p "$TARGET_DB_PORT" -U "$TARGET_DB_USER" -d "$db_name" > "$BACKUP_FILE" 2>&1; then
            BACKUP_COUNT=$((BACKUP_COUNT + 1))
            log_message "Backup created for database '$db_name'"
        else
            log_message "WARNING: Backup failed for database '$db_name'. Continuing anyway."
        fi
    fi
done

log_message "Created backups for $BACKUP_COUNT database(s)"

#============================
# RESTORE EACH DATABASE FROM DUMP
#============================
RESTORED_COUNT=0
FAILED_COUNT=0
FAILED_DBS=()

for DUMP_FILE in "${DUMP_FILES_ARRAY[@]}"; do
    # Extract database name from filename (format: DBNAME_TIMESTAMP.sql.gz)
    filename=$(basename "$DUMP_FILE" .sql.gz)
    DB_NAME=$(echo "$filename" | sed -E 's/^(.+)_[0-9]{8}_[0-9]{6}$/\1/')
    
    if [ -z "$DB_NAME" ]; then
        log_message "ERROR: Could not extract database name from filename: $DUMP_FILE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_DBS+=("$DUMP_FILE")
        continue
    fi
    
    log_message "Starting restore for database '$DB_NAME' from: $DUMP_FILE"
    
    # Check if database exists, create if not
    DB_EXISTS=$(psql -h "$TARGET_DB_HOST" -p "$TARGET_DB_PORT" -U "$TARGET_DB_USER" -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';" | tr -d ' ')
    
    if [ -z "$DB_EXISTS" ]; then
        log_message "Database '$DB_NAME' does not exist. Creating it."
        if psql -h "$TARGET_DB_HOST" -p "$TARGET_DB_PORT" -U "$TARGET_DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";" 2>&1; then
            log_message "SUCCESS: Database '$DB_NAME' created"
        else
            log_message "ERROR: Failed to create database '$DB_NAME'"
            FAILED_COUNT=$((FAILED_COUNT + 1))
            FAILED_DBS+=("$DB_NAME")
            continue
        fi
    fi
    
    # Restore the dump
    if gunzip -c "$DUMP_FILE" | psql -h "$TARGET_DB_HOST" -p "$TARGET_DB_PORT" -U "$TARGET_DB_USER" -d "$DB_NAME" 2>&1; then
        log_message "SUCCESS: Database '$DB_NAME' restored from $DUMP_FILE"
        RESTORED_COUNT=$((RESTORED_COUNT + 1))
    else
        log_message "ERROR: Failed to restore database '$DB_NAME' from $DUMP_FILE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_DBS+=("$DB_NAME")
    fi
done

#============================
# FINALIZE RESTORE PROCESS
#============================
if [ $FAILED_COUNT -eq 0 ]; then
    log_message "SUCCESS: All ${RESTORED_COUNT} database(s) restored successfully"
    
    # Mark as processed
    touch "$PROCESSED_FLAG"
    log_message "Marked dumps with timestamp $LATEST_TIMESTAMP as processed"
    
    # Remove ready flag
    rm -f "$READY_FLAG"
    log_message "Removed dump_ready.flag"
    
    # Delete old processed dumps (keep 10 newest timestamps)
    ls -t "$DUMP_DIR"/restore_*.processed 2>/dev/null | tail -n +11 | xargs -r rm -f
    log_message "Old processed dump files cleaned."
    
else
    log_message "ERROR: Restore completed with failures: ${RESTORED_COUNT} successful, ${FAILED_COUNT} failed"
    log_message "Failed databases: ${FAILED_DBS[*]}"
    
    # Optionally restore from backups if restore failed
    if [ $BACKUP_COUNT -gt 0 ]; then
        log_message "WARNING: Some databases failed to restore. Consider restoring from backups in: $BACKUP_DIR"
    fi
    
    exit 1
fi

log_message "Database restore process finished successfully."
