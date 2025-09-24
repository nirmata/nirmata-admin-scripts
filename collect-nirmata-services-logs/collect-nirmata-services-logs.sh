#!/bin/bash

if [ $# -lt 4 ]; then
  echo "Usage: <script> <NirmataURL> <Namespace> <LogDurationInMinutes> <Nirmata-service1> <Nirmata-service2> ..."
  echo ""
  echo "Eg: <script> https://www.nirmata.io nirmata 10 config cluster-processor"
  echo "Nirmata Services: activity,catalog,cluster,config,environments,users"
else
  NIRMATAURL=$1
  NAMESPACE=$2
  LOG_DURATION=$3
  shift 3
  SERVICE_NAMES=("$@")

  echo "====================="
  echo "Enabling DEBUG Mode for all services"
  echo "====================="

  for SERVICENAME in "${SERVICE_NAMES[@]}"; do
    for i in {1..5}; do
      curl -s -k -X PUT -d "{\"name\": \"com.nirmata\", \"level\": \"DEBUG\"}" "$NIRMATAURL/$SERVICENAME/logger?name=com.nirmata" &
    done
  done

  wait
  sleep 10

  echo "====================="
  echo "Capturing logs for all services for $LOG_DURATION minutes"
  echo "====================="

  for SERVICENAME in "${SERVICE_NAMES[@]}"; do
    (
      Replicas=$(kubectl -n $NAMESPACE get deployment $SERVICENAME -o jsonpath='{.spec.replicas}')
      echo "Current Replicas of $SERVICENAME: $Replicas"
      echo "Scaling deployment $SERVICENAME to 1"
      kubectl -n $NAMESPACE scale deployment $SERVICENAME --replicas=1
      sleep 5

      pod_name=$(kubectl get pods -n $NAMESPACE -l nirmata.io/service.name=$SERVICENAME -o jsonpath='{.items[0].metadata.name}')
      current_datetime=$(date +%Y-%m-%d_%H-%M-%S)
      log_file="${SERVICENAME}-${current_datetime}.log"
      echo "Collecting logs of $pod_name for $LOG_DURATION minutes and saving in file named '$log_file'"
      kubectl -n $NAMESPACE logs -f $pod_name --tail=500 >> "$log_file" & sleep $((LOG_DURATION * 60)) ; kill $!
      sleep 10
    ) &
  done

  wait

  echo "====================="
  echo "Disabling DEBUG Mode for all services"
  echo "====================="

  for SERVICENAME in "${SERVICE_NAMES[@]}"; do
    for i in {1..5}; do
      curl -s -k -X PUT -d "{\"name\": \"com.nirmata\", \"level\": \"WARN\"}" "$NIRMATAURL/$SERVICENAME/logger?name=com.nirmata" &
    done
  done

  wait
  sleep 10

  for SERVICENAME in "${SERVICE_NAMES[@]}"; do
    Replicas=$(kubectl -n $NAMESPACE get deployment $SERVICENAME -o jsonpath='{.spec.replicas}')
    echo "Scaling deployment $SERVICENAME back to $Replicas"
    kubectl -n $NAMESPACE scale deployment $SERVICENAME --replicas=$Replicas
    sleep 5
  done

  current_datetime=$(date +%Y-%m-%d_%H-%M-%S)
  zip_file="nirmata-logs-${current_datetime}.zip"
  echo "Zipping log files into $zip_file"
  zip "$zip_file" *.log

  echo "The logs are saved in the current directory as '$zip_file'. Please share it via JIRA/Email."
fi