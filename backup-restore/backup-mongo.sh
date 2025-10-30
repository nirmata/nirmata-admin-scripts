#!/bin/bash

################################################################################
# MongoDB Backup Script with Namespace Support
# Enhanced to support any namespace as parameter
################################################################################

#set -x

showcollectionscount() {
#unix_timestamp=$(($(date +%s%N)/1000000))

cat << EOF > commands_${1}.js
use $1
var timestamp = $unix_timestamp;
db.getCollectionNames().forEach(function(col) {
var size = db[col].find({"createdOn":{\$lt:timestamp}}).count();
print(col+":"+size);
})
EOF

}

getdb_version() {
cat << EOF > dbVersion_${1}.js
use $1
db.DBVERSION.find()
EOF
}

drop_db() {
cat << EOF > dropdb_${1}.js
use $1
db.dropDatabase()
EOF
}

## main
# Arguments: backup_location [namespace]
backup_location=$1
NAMESPACE="${2:-nirmata}"  # Default to nirmata if not specified

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <backup-folder> [namespace]"
    echo ""
    echo "Examples:"
    echo "  $0 /tmp/backups                  # Backup nirmata namespace"
    echo "  $0 /tmp/backups p2               # Backup p2 namespace"
    echo "  $0 /tmp/backups pe420            # Backup pe420 namespace"
    exit 1
fi

echo "========================================"
echo "MongoDB Backup Script"
echo "========================================"
echo "Target Namespace: $NAMESPACE"
echo "Backup Location: $backup_location"
echo "========================================"
echo ""

# List all mongo pods
mongos="mongodb-0 mongodb-1 mongodb-2"

for mongo in $mongos
do
    # Adjust the command below with authentication details if necessary
    cur_mongo=$(kubectl -n "$NAMESPACE" exec $mongo -c mongodb -- mongo --quiet --eval "printjson(rs.isMaster())" 2>&1)

    if echo "$cur_mongo" | grep -q '"ismaster" : true'; then
        echo "$mongo is master"
        mongo_master=$mongo
        break # Assuming you only need one master, exit loop after finding it
    fi
done

if [ -n "$mongo_master" ]; then
    echo "The primary MongoDB replica is: $mongo_master"
else
    echo "No primary MongoDB replica found in namespace: $NAMESPACE"
    exit 1 # It seems this exit was intended to be here to halt the script if no master is found.
fi

MONGO_MASTER=$mongo_master

# Database names based on namespace
NIRMATA_SERVICES="Activity-${NAMESPACE} Availability-cluster-hc-${NAMESPACE} Availability-env-app-${NAMESPACE} Catalog-${NAMESPACE} Cluster-${NAMESPACE} Config-${NAMESPACE} Environments-${NAMESPACE} Users-${NAMESPACE} TimeSeries-${NAMESPACE}"

echo "Databases to backup:"
for db in $NIRMATA_SERVICES; do
    echo "  - $db"
done
echo ""

NIRMATA_HOST_BACKUP_FOLDER=/tmp/backup-${NAMESPACE}
NIRMATA_POD_BACKUP_FOLDER=/tmp/${NAMESPACE}-backups

kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- mkdir -p $NIRMATA_POD_BACKUP_FOLDER
kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- rm -rf $NIRMATA_POD_BACKUP_FOLDER/*
kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- mkdir -p $NIRMATA_POD_BACKUP_FOLDER/logs
kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- touch $NIRMATA_POD_BACKUP_FOLDER/logs/backup-status.log

# convert current date into unix time.
unix_timestamp=$(($(date +%s%N)/1000000))

mkdir -p $NIRMATA_HOST_BACKUP_FOLDER/$(date +%m-%d-%y)/$(date +"%H-%M")

BACKUP_DIR="$NIRMATA_HOST_BACKUP_FOLDER/$(date +%m-%d-%y)/$(date +"%H-%M")"

echo "Backup directory: $BACKUP_DIR"
echo ""

#echo $unix_timestamp

for nsvc in $NIRMATA_SERVICES
do
        echo
        echo "-------------------------------------------------------"
        echo "Backing up $nsvc db using mongodump"
        echo "-------------------------------------------------------"
        echo
        kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- touch $NIRMATA_POD_BACKUP_FOLDER/logs/${nsvc}_backup.log
        sleep 2
        kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "mongodump --gzip --db=$nsvc --archive=$NIRMATA_POD_BACKUP_FOLDER/$nsvc.gz 2>&1 | tee -a $NIRMATA_POD_BACKUP_FOLDER/logs/${nsvc}_backup.log"
        if [[ $? != 0 ]]; then
                kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "echo \"Could not backup $nsvc database on $(date)\" | tee -a $NIRMATA_POD_BACKUP_FOLDER/logs/backup-status.log"
        else
                echo
                file1=""
                file2=""
                file3=""
                file4=""

                file1="$BACKUP_DIR/${nsvc}_objcount.txt"
                file2="$BACKUP_DIR/${nsvc}-test_objcount.txt"
                file3="$BACKUP_DIR/${nsvc}_dbVersion.txt"
                file4="$BACKUP_DIR/${nsvc}-test_dbVersion.txt"

                showcollectionscount $nsvc
                kubectl -n "$NAMESPACE" cp commands_${nsvc}.js $MONGO_MASTER:/tmp/ -c mongodb

                getdb_version $nsvc
                kubectl -n "$NAMESPACE" cp dbVersion_${nsvc}.js $MONGO_MASTER:/tmp/ -c mongodb

                echo
                echo "-------------------------------------------------------------------------"
                echo "Displaying collection count for ${nsvc} database                         "
                echo "-------------------------------------------------------------------------"
                echo
                kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "mongo --quiet < /tmp/commands_${nsvc}.js" | grep -v "switched to db ${nsvc}" > $file1
                kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "mongo --quiet < /tmp/dbVersion_${nsvc}.js" | grep -v "switched to db ${nsvc}" > $file3
                kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "mongorestore --drop --gzip --archive=$NIRMATA_POD_BACKUP_FOLDER/$nsvc.gz --nsFrom \"${nsvc}.*\" --nsTo \"${nsvc}-test.*\" --noIndexRestore --nsInclude \"${nsvc}.*\""

                showcollectionscount ${nsvc}-test
                kubectl -n "$NAMESPACE" cp commands_${nsvc}-test.js $MONGO_MASTER:/tmp/
                kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "mongo --quiet < /tmp/commands_${nsvc}-test.js" | grep -v "switched to db ${nsvc}-test" > $file2
                #echo
                #echo "-------------------------------------------------------------------------"
                #echo "Displaying collection count for ${nsvc}-test database                    "
                #echo "-------------------------------------------------------------------------"
                #echo


                getdb_version ${nsvc}-test
                kubectl -n "$NAMESPACE" cp dbVersion_${nsvc}-test.js $MONGO_MASTER:/tmp/ -c mongodb
                kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "mongo --quiet < /tmp/dbVersion_${nsvc}-test.js" | grep -v "switched to db ${nsvc}-test" > $file4

                drop_db ${nsvc}-test
                kubectl -n "$NAMESPACE" cp dropdb_${nsvc}-test.js $MONGO_MASTER:/tmp/ -c mongodb
                kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "mongo --quiet < /tmp/dropdb_${nsvc}-test.js"



                diff_output="$(diff --brief "$file1" "$file2")"

                # check if there's any output from the diff command
                if [ -n "$diff_output" ]; then
                        echo "There is a difference between the files. The backup file could be corrupted as the file count between the ${nsvc} and the ${nsvc}-test databases does not match before and after " >> $BACKUP_DIR/dbvrsn_objcnt.log
                fi

                diff_output2="$(diff --brief "$file3" "$file4")"

                # check if there's any output from the diff command
                if [ -n "$diff_output2" ]; then
                        echo "The dbVersion does not seem to match between the the ${nsvc} and the ${nsvc}-test databases" >> $BACKUP_DIR/dbvrsn_objcnt.log
                fi



        fi
done

kubectl -n "$NAMESPACE" exec $MONGO_MASTER -c mongodb -- sh -c "cd /tmp; tar cvf ${NAMESPACE}-backups.tar ${NAMESPACE}-backups/"

kubectl -n "$NAMESPACE" cp $MONGO_MASTER:/tmp/${NAMESPACE}-backups.tar -c mongodb $BACKUP_DIR/${NAMESPACE}-backups.tar

tar -xvf $BACKUP_DIR/${NAMESPACE}-backups.tar -C $BACKUP_DIR

# echo "${NAMESPACE}-backups.tar extracted to: $BACKUP_DIR/${NAMESPACE}-backups at $(date)" > ${NAMESPACE}_backup_directory_path_details.txt

kubectl -n "$NAMESPACE" cp $MONGO_MASTER:$NIRMATA_POD_BACKUP_FOLDER/logs/backup-status.log -c mongodb $BACKUP_DIR/backup-status.log

mv *.js /tmp 2>/dev/null || true


# Copy over the contents.
cp -r $NIRMATA_HOST_BACKUP_FOLDER/* "$backup_location"
# Remove the source directory after successful copy.
rm -rf $NIRMATA_HOST_BACKUP_FOLDER

echo ""
echo "========================================"
echo "Backup Complete!"
echo "========================================"
echo "Namespace: $NAMESPACE"
echo "Backup saved to: $backup_location"
echo ""
echo "To restore this backup to another namespace:"
echo "  cd ~/nirmata-admin-scripts/backup-restore"
echo "  ./restore.sh $backup_location/$(date +%m-%d-%y)/$(date +"%H-%M")/${NAMESPACE}-backups <target-namespace>"
echo ""
