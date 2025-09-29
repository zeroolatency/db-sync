#!/bin/bash

SOURCE_DB_HOST="localhost"
SOURCE_DB_PORT="5433"
SOURCE_DB_NAME="source_db"
SOURCE_DB_USER="postgres"
TARGET_VM_HOST="target-vm-ip"
TARGET_VM_USER="postgres"
DUMP_FILE="/data/postgres/source_database_dump.sql"

echo "Starting automatic transfer..."

echo "Creating database dump..."
docker exec postgres_instance_1 pg_dump -h $SOURCE_DB_HOST -p $SOURCE_DB_PORT -U $SOURCE_DB_USER -d $SOURCE_DB_NAME > $DUMP_FILE

if [ $? -eq 0 ]; then
    echo "✓ Dump created successfully"
    
    gzip $DUMP_FILE
    echo "✓ Dump compressed"
    
    echo "Transferring to target VM..."
    scp ${DUMP_FILE}.gz $TARGET_VM_USER@$TARGET_VM_HOST:/var/backups/postgres/
    
    if [ $? -eq 0 ]; then
        echo "✓ Transfer completed successfully"
        
        ssh $TARGET_VM_USER@$TARGET_VM_HOST "echo 'NEW_DUMP_READY' > /var/backups/postgres/dump_ready.flag"
        echo "✓ Target VM notified"
        
    else
        echo "✗ Transfer failed"
        exit 1
    fi
else
    echo "✗ Dump creation failed"
    exit 1
fi

echo "Automatic transfer completed!"