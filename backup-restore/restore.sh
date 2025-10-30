#!/bin/bash

################################################################################
# MongoDB Restore Script
# Enhanced with logging and optimized batch size for 16Gi memory pods
################################################################################

## Configuration
BATCH_SIZE="${BATCH_SIZE:-300}"                      # Optimized for 16Gi pods (was 10)
TIMESERIES_BATCH_SIZE="${TIMESERIES_BATCH_SIZE:-100}" # Smaller for TimeSeries to avoid errors
LOG_DIR="./restore_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/restore_${TIMESTAMP}.log"
STATUS_FILE="${LOG_DIR}/restore_status_${TIMESTAMP}.txt"

# Create log directory
mkdir -p "$LOG_DIR"

## Logging function
log_and_echo() {
    echo "$1" | tee -a "$LOG_FILE"
}

log_and_echo "========================================"
log_and_echo "MongoDB Restore Script"
log_and_echo "Started at: $(date)"
log_and_echo "Batch Size (regular): $BATCH_SIZE"
log_and_echo "Batch Size (TimeSeries): $TIMESERIES_BATCH_SIZE"
log_and_echo "========================================"
echo ""

## main
# Parse arguments
backupfolder=$1
NAMESPACE="${2:-nirmata}"  # Default to nirmata if not specified

if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
        echo -e "\nUsage: $0 <backup-folder> [namespace]\n"
        echo "Examples:"
        echo "  $0 /backup/nirmata-backups           # Restore to nirmata namespace"
        echo "  $0 /backup/p2-backups pe420          # Restore p2 backup to pe420 namespace"
        echo ""
        echo "Environment variables:"
        echo "  BATCH_SIZE=300 (default)              - Batch size for regular databases"
        echo "  TIMESERIES_BATCH_SIZE=100 (default)   - Batch size for TimeSeries databases"
        exit 1
fi

log_and_echo "Backup folder: $backupfolder"
log_and_echo "Target namespace: $NAMESPACE"

if kubectl get pods -n "$NAMESPACE" --no-headers | egrep -v 'mongo|zk|kafka|kafka-controller' 1> /dev/null; then
        log_and_echo "ERROR: Please scale down non shared services in $NAMESPACE before performing the restore"
        exit 1
fi

# List all mongo pods
mongos="mongodb-0 mongodb-1 mongodb-2"

log_and_echo "Finding MongoDB master in $NAMESPACE..."
for mongo in $mongos; do
    # Check if the pod is the MongoDB master
    cur_mongo=$(kubectl -n "$NAMESPACE" exec $mongo -c mongodb -- bash -c 'mongo --eval "db.isMaster().ismaster" --quiet' 2>&1)
    if [[ "$cur_mongo" == "true" ]]; then
        log_and_echo "✓ $mongo is master"
        mongo_master=$mongo
        break
    fi
done

MONGO_MASTER=$mongo_master

if [[ -z $MONGO_MASTER ]]; then
        log_and_echo "ERROR: Unable to find the mongo master. Please check the mongo cluster. Exiting!"
        exit 1
fi

# Initialize status file
echo "# MongoDB Restore Status - $(date)" > "$STATUS_FILE"
echo "# Backup Source: $backupfolder" >> "$STATUS_FILE"
echo "# Target Namespace: $NAMESPACE" >> "$STATUS_FILE"
echo "# MongoDB Master: $MONGO_MASTER" >> "$STATUS_FILE"
echo "# Batch Size (regular): $BATCH_SIZE" >> "$STATUS_FILE"
echo "# Batch Size (TimeSeries): $TIMESERIES_BATCH_SIZE" >> "$STATUS_FILE"
echo "========================================" >> "$STATUS_FILE"
echo "" >> "$STATUS_FILE"

# Auto-detect source namespace from backup files
log_and_echo "Detecting backup files..."
first_backup=$(ls "$backupfolder"/*.gz 2>/dev/null | head -1)
if [[ -z "$first_backup" ]]; then
    log_and_echo "ERROR: No backup files found in $backupfolder"
    exit 1
fi

# Extract namespace suffix from backup filename (e.g., Activity-p2.gz -> p2)
first_basename=$(basename "$first_backup" .gz)
SOURCE_NS=$(echo "$first_basename" | sed 's/.*-//')

log_and_echo "Source namespace detected: $SOURCE_NS"
log_and_echo "Target namespace: $NAMESPACE"

# Build database list dynamically based on source namespace
mongodbs="Activity-${SOURCE_NS} Availability-cluster-hc-${SOURCE_NS} Availability-env-app-${SOURCE_NS} Catalog-${SOURCE_NS} Cluster-${SOURCE_NS} Config-${SOURCE_NS} Environments-${SOURCE_NS} Users-${SOURCE_NS} TimeSeries-${SOURCE_NS}"

log_and_echo ""
log_and_echo "========================================"
log_and_echo "Starting restore of databases"
log_and_echo "========================================"

total_start=$(date +%s)
success_count=0
failed_count=0
db_count=0
total_dbs=$(echo $mongodbs | wc -w | tr -d ' ')

# For each database
for source_db in $mongodbs; do
  db_count=$((db_count + 1))
  db_start=$(date +%s)
  
  # Calculate target database name (replace source namespace with target namespace)
  db_basename=$(echo "$source_db" | sed "s/-${SOURCE_NS}$//")
  target_db="${db_basename}-${NAMESPACE}"
  backup_file="${source_db}.gz"
  
  echo "" | tee -a "$LOG_FILE"
  log_and_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_and_echo "[$db_count/$total_dbs] Restoring: $backup_file → $target_db"
  log_and_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check if backup file exists
  if [[ ! -f "$backupfolder/$backup_file" ]]; then
    log_and_echo "  ✗ Backup file not found: $backupfolder/$backup_file"
    echo "❌ FAILED: $target_db - Backup file not found" >> "$STATUS_FILE"
    failed_count=$((failed_count + 1))
    continue
  fi
  
  backup_size=$(du -h "$backupfolder/$backup_file" | cut -f1)
  log_and_echo "  Backup size: $backup_size"

  # Determine batch size based on database type
  if [[ "$target_db" == *"TimeSeries"* ]]; then
    current_batch_size=$TIMESERIES_BATCH_SIZE
    log_and_echo "  Using TimeSeries batch size: $current_batch_size (prevents demux errors)"
  else
    current_batch_size=$BATCH_SIZE
    log_and_echo "  Using regular batch size: $current_batch_size"
  fi

  # Copy the backup file to the MongoDB pod
  log_and_echo "  → Copying backup to pod..."
  if kubectl -n "$NAMESPACE" cp "$backupfolder/$backup_file" "$MONGO_MASTER:/tmp/${backup_file}" -c mongodb >> "$LOG_FILE" 2>&1; then
    log_and_echo "  ✓ Backup copied"
  else
    log_and_echo "  ✗ Failed to copy backup to pod"
    echo "❌ FAILED: $target_db - Copy failed" >> "$STATUS_FILE"
    failed_count=$((failed_count + 1))
    continue
  fi

  # Connect to the MongoDB pod and restore the database
  log_and_echo "  → Running mongorestore to $target_db..."
  
  # If source and target namespaces differ, use nsFrom/nsTo for transformation
  if [[ "$SOURCE_NS" != "$NAMESPACE" ]]; then
    restore_cmd="mongorestore --drop --gzip --archive=/tmp/${backup_file} --noIndexRestore --batchSize=$current_batch_size --numInsertionWorkersPerCollection=4 --nsFrom='${source_db}.*' --nsTo='${target_db}.*' --bypassDocumentValidation -v"
  else
    restore_cmd="mongorestore --drop --gzip --db=${target_db} --archive=/tmp/${backup_file} --noIndexRestore --batchSize=$current_batch_size --numInsertionWorkersPerCollection=4 --bypassDocumentValidation -v"
  fi
  
  if kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "$restore_cmd" >> "$LOG_FILE" 2>&1; then
    
    db_end=$(date +%s)
    db_duration=$((db_end - db_start))
    
    log_and_echo "  ✓ Database restored successfully (${db_duration}s)"
    echo "✅ SUCCESS: $target_db (${db_duration}s, batch: $current_batch_size)" >> "$STATUS_FILE"
    success_count=$((success_count + 1))
  else
    log_and_echo "  ✗ Database restore failed"
    echo "❌ FAILED: $target_db" >> "$STATUS_FILE"
    failed_count=$((failed_count + 1))
  fi

  # Delete the backup file
  log_and_echo "  → Cleaning up..."
  kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "rm -f /tmp/${backup_file}" >> "$LOG_FILE" 2>&1

done

total_end=$(date +%s)
total_duration=$((total_end - total_start))
total_minutes=$((total_duration / 60))
total_seconds=$((total_duration % 60))

echo "" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "========================================" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "        RESTORE SUMMARY" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "========================================" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "Total Databases:  $total_dbs" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "✅ Successful:    $success_count" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "❌ Failed:        $failed_count" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "⏱️  Total Time:    ${total_minutes}m ${total_seconds}s" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "📦 Batch Size:    $BATCH_SIZE (regular), $TIMESERIES_BATCH_SIZE (TimeSeries)" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "========================================" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "" | tee -a "$LOG_FILE" | tee -a "$STATUS_FILE"
echo "Completed at: $(date)" | tee -a "$LOG_FILE"
echo "📄 Detailed log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "📋 Status file:  $STATUS_FILE" | tee -a "$LOG_FILE"
echo ""

if [[ $failed_count -gt 0 ]]; then
    echo "⚠️  WARNING: Some databases failed to restore!"
    echo "Check logs: $LOG_FILE"
    exit 1
else
    echo "✅ All databases restored successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Rebuild indexes (if needed)"
    echo "  2. Verify data integrity"
    echo "  3. Scale up services: kubectl scale deployment --all --replicas=1 -n nirmata"
    exit 0
fi
