#!/bin/bash

## main

echo "========================================="
echo "  MongoDB Restore Script for Nirmata"
echo "========================================="
echo ""

if kubectl get pods -n nirmata --no-headers | egrep -v 'mongo|zk|kafka|kafka-controller' 1> /dev/null; then
        echo -e "\n❌ ERROR: Please scale down non shared services before performing the restore"
        echo "Run: kubectl scale deployment --all --replicas=0 -n nirmata"
        echo ""
        exit 1
fi

if [[ $# != 1 ]]; then
        echo -e "\nUsage: $0 <backup-folder>\n"
        echo "Example: $0 /path/to/backup"
        echo ""
        exit 1
fi

if [[ ! -d "$1" ]]; then
        echo -e "\n❌ ERROR: Backup folder '$1' does not exist!\n"
        exit 1
fi

# List all mongo pods
mongos="mongodb-0 mongodb-1 mongodb-2"

echo "=== Finding MongoDB Master ==="
for mongo in $mongos; do
    # Check if the pod is the MongoDB master
    cur_mongo=$(kubectl -n nirmata exec $mongo -c mongodb -- bash -c 'mongo --eval "db.isMaster().ismaster" --quiet' 2>&1)
    if [[ "$cur_mongo" == "true" ]]; then
        echo "  ✓ $mongo is master"
        mongo_master=$mongo
        break
    fi
done
echo ""

MONGO_MASTER=$mongo_master

if [[ -z $MONGO_MASTER ]]; then
        echo "Unable to find the mongo master. Please check the mongo cluster. Exiting!"
        exit 1
fi

rm -f /tmp/restore-status.txt
touch /tmp/restore-status.txt

backupfolder=$1

# Get the list of all databases
mongodbs="Activity-nirmata Availability-cluster-hc-nirmata Availability-env-app-nirmata Catalog-nirmata Cluster-nirmata Config-nirmata Environments-nirmata Users-nirmata TimeSeries-nirmata"

# Validate backup files exist
echo "=== Validating backup files ==="
for db in $mongodbs; do
  if [[ ! -f "$backupfolder/${db}.gz" ]]; then
    echo "ERROR: Backup file $backupfolder/${db}.gz not found!"
    exit 1
  fi
  filesize=$(du -h "$backupfolder/${db}.gz" 2>/dev/null | cut -f1)
  echo "  ✓ ${db}.gz exists (size: ${filesize:-unknown})"
done
echo ""
#mongodbs="Activity-nirmata"
#mongodbs="Availability-cluster-hc-nirmata"
#mongodbs="Availability-env-app-nirmata"
#mongodbs="Catalog-nirmata"
#mongodbs="Cluster-nirmata"
#mongodbs="Config-nirmata"
#mongodbs="Environments-nirmata"
#mongodbs="Users-nirmata"
#mongodbs="TimeSeries-nirmata"

# For each database
echo "=== Starting restore process ==="
for db in $mongodbs; do

  echo "--- Restoring ${db} ---"
  
  # Copy the backup file to the MongoDB pod
  echo "  Copying ${db}.gz to MongoDB pod..."
  kubectl -n nirmata cp $backupfolder/${db}.gz $MONGO_MASTER:/tmp/${db}.gz -c mongodb
  
  if [ $? -ne 0 ]; then
    echo "  ERROR: Failed to copy ${db}.gz to pod" | tee -a /tmp/restore-status.txt
    continue
  fi

  # Connect to the MongoDB pod and restore the database
  echo "  Restoring ${db} to MongoDB..."
  kubectl -n nirmata exec $MONGO_MASTER -c mongodb -- sh -c "mongorestore --drop --gzip --db=${db} --archive=/tmp/${db}.gz --noIndexRestore --batchSize=100 -v"

  # Check the status of the restore
  if [ $? -eq 0 ]; then
    echo "  ✓ Database ${db} restored successfully" | tee -a /tmp/restore-status.txt
  else
    echo "  ✗ Database ${db} restore failed" | tee -a /tmp/restore-status.txt
  fi

  # Delete the backup file
  kubectl -n nirmata exec $MONGO_MASTER -c mongodb -- sh -c "rm -f /tmp/${db}.gz"
  
  echo ""

done

# Post-restore verification
echo "=== Restore Verification ==="
echo "Checking TimeSeries-nirmata data..."
ts_count=$(kubectl -n nirmata exec $MONGO_MASTER -c mongodb -- mongo --quiet --eval 'db.getSiblingDB("TimeSeries-nirmata").timeseries.countDocuments()')
echo "  TimeSeries documents: $ts_count"

echo "Checking Environments-nirmata data..."
env_count=$(kubectl -n nirmata exec $MONGO_MASTER -c mongodb -- mongo --quiet --eval 'db.getSiblingDB("Environments-nirmata").getCollectionNames().length')
echo "  Environments collections: $env_count"

echo ""
echo "=== Restore Summary ==="
cat /tmp/restore-status.txt

echo ""
echo "========================================="
echo "  Next Steps"
echo "========================================="
echo "1. Scale up application deployments:"
echo "   kubectl scale deployment --all --replicas=2 -n nirmata"
echo ""
echo "2. Verify pods start successfully:"
echo "   kubectl get pods -n nirmata -w"
echo ""
echo "3. Check for errors in environments pod:"
echo "   kubectl logs -n nirmata -l app=environments --tail=100"
echo ""
echo "4. If you still see 503 errors, check:"
echo "   kubectl get endpoints -n nirmata | grep environments"
echo "========================================="
