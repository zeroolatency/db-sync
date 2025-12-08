#!/bin/bash

set -euo pipefail

#===============================
# CONFIGURATION
#===============================
SOURCE_DB_HOST="host.docker.internal"
SOURCE_DB_PORT="5433"
SOURCE_DB_NAME="postgres"
SOURCE_DB_USER="postgres"
SOURCE_DB_PASSWORD="password"

TARGET_VM_HOST="host.docker.internal"
TARGET_VM_USER="postgres"

DUMP_DIR="./backups/postgres"
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/postgres_dump.log"

CONTAINER_NAME="postgres_instance_1"

#===============================
# PREPARE DIRECTORIES
#===============================
mkdir -p "$DUMP_DIR"
mkdir -p "$LOG_DIR"

#===============================
# LOGGING FUNCTION
#===============================
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

log_message "Starting database dump process"

#===============================
# CHECK CONTAINER RUNNING
#===============================
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    log_message "ERROR: PostgreSQL container '$CONTAINER_NAME' is not running"
    exit 1
fi

#===============================
# GET LIST OF ALL DATABASES
#===============================
log_message "Retrieving list of databases from PostgreSQL instance"

# Get list of all databases (excluding system databases)
DATABASES=$(docker exec \
    -e PGPASSWORD="$SOURCE_DB_PASSWORD" \
    "$CONTAINER_NAME" \
    psql -h "$SOURCE_DB_HOST" \
         -p "$SOURCE_DB_PORT" \
         -U "$SOURCE_DB_USER" \
         -d postgres \
         -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

if [ -z "$DATABASES" ]; then
    log_message "WARNING: No databases found (excluding system databases)"
    # Fallback: include postgres database if no others found
    DATABASES=$(docker exec \
        -e PGPASSWORD="$SOURCE_DB_PASSWORD" \
        "$CONTAINER_NAME" \
        psql -h "$SOURCE_DB_HOST" \
             -p "$SOURCE_DB_PORT" \
             -U "$SOURCE_DB_USER" \
             -d postgres \
             -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;")
fi

# Convert to array and trim whitespace
DATABASES_ARRAY=()
while IFS= read -r db; do
    db=$(echo "$db" | xargs)  # Trim whitespace
    if [ -n "$db" ]; then
        DATABASES_ARRAY+=("$db")
    fi
done <<< "$DATABASES"

if [ ${#DATABASES_ARRAY[@]} -eq 0 ]; then
    log_message "ERROR: No databases found to dump"
    exit 1
fi

log_message "Found ${#DATABASES_ARRAY[@]} database(s) to dump: ${DATABASES_ARRAY[*]}"

#===============================
# DUMP EACH DATABASE
#===============================
DUMPED_COUNT=0
FAILED_COUNT=0

for DB_NAME in "${DATABASES_ARRAY[@]}"; do
    DUMP_FILE="${DUMP_DIR}/${DB_NAME}_${TIMESTAMP}.sql"
    
    log_message "Creating pg_dump for database '$DB_NAME': $DUMP_FILE"
    
    if docker exec \
        -e PGPASSWORD="$SOURCE_DB_PASSWORD" \
        "$CONTAINER_NAME" \
        pg_dump -h "$SOURCE_DB_HOST" \
                -p "$SOURCE_DB_PORT" \
                -U "$SOURCE_DB_USER" \
                -d "$DB_NAME" \
        > "$DUMP_FILE" 2>&1; then
        
        # Check if dump file was created and has content
        if [ -s "$DUMP_FILE" ]; then
            # Compress the dump file
            log_message "Compressing dump file for '$DB_NAME'"
            gzip "$DUMP_FILE"
            DUMP_FILE="${DUMP_FILE}.gz"
            
            log_message "SUCCESS: Dump created and compressed for database '$DB_NAME': $DUMP_FILE"
            DUMPED_COUNT=$((DUMPED_COUNT + 1))
        else
            log_message "ERROR: Dump file for '$DB_NAME' is empty or was not created"
            rm -f "$DUMP_FILE"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    else
        log_message "ERROR: Failed to create dump for database '$DB_NAME'"
        rm -f "$DUMP_FILE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

if [ $DUMPED_COUNT -eq 0 ]; then
    log_message "ERROR: No dumps created successfully"
    exit 1
fi

#===============================
# CREATE DUMP READY FLAG FILE
#===============================
log_message "Creating dump ready flag file"
mkdir -p "$DUMP_DIR" || true
FLAG_FILE="${DUMP_DIR}/dump_ready.flag"
if echo 'NEW_DUMP_READY' > "$FLAG_FILE" 2>&1; then
    log_message "SUCCESS: Dump ready flag file created: $FLAG_FILE"
    if [ -f "$FLAG_FILE" ]; then
        log_message "Verified: Flag file exists at $FLAG_FILE"
    else
        log_message "WARNING: Flag file command succeeded but file not found"
    fi
else
    log_message "ERROR: Failed to create dump ready flag file"
fi



log_message "Dump process completed: ${DUMPED_COUNT} successful, ${FAILED_COUNT} failed"

#===============================
# TRANSFER FILE TO TARGET VM
#===============================
# log_message "Transferring dump to target VM: $TARGET_VM_HOST"

# if scp -o StrictHostKeyChecking=no "$DUMP_FILE" "$TARGET_VM_USER@$TARGET_VM_HOST:/var/backups/postgres/"; then
#     log_message "SUCCESS: Dump file transferred"
# else
#     log_message "ERROR: Failed to transfer dump"
#     exit 1
# fi

#===============================
# CLEAN UP OLD FILES
#===============================
# find "$DUMP_DIR" -name "source_db_*.sql.gz" -mtime +7 -delete
# log_message "Old dump files cleaned"

# #===============================
# # NOTIFY TARGET VM
# #===============================


# log_message "Target VM notified"

# log_message "Database dump process completed successfully"
