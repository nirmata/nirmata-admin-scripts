#!/bin/bash

# Check for required arguments
if [ $# -lt 2 ]; then
  echo "Usage: $0 <nirmata_url> <api_token>"
  echo ""
  echo "Example:"
  echo "  $0 https://www.nirmata.io EjJwbMsN9gtYD7nmFFMY4sVKPo3kHa5ggDjH4+FM1HjOymh9ZmR8NHeUzWy2EjwGkVzDOe0ezvenhFy7G4tmQw=="
  echo ""
  exit 1
fi

# Nirmata API Configuration from arguments
NIRMATA_URL="$1"
API_TOKEN="$2"

# Auto-fetch Environment Root ID
echo "Fetching Environment Root ID..."
ENVIRONMENT_ID=$(curl -s -H "Authorization: NIRMATA-API ${API_TOKEN}" \
  "${NIRMATA_URL}/environments/api/Root" | jq -r '.[0].id' 2>/dev/null)

if [ -z "$ENVIRONMENT_ID" ] || [ "$ENVIRONMENT_ID" = "null" ]; then
  echo "Error: Could not fetch Environment Root ID"
  exit 1
fi

# Output CSV file
OUTPUT_FILE="localhost_clusters_$(date +%Y%m%d_%H%M%S).csv"

# Initialize counters
total_clusters=0
localhost_clusters=0

echo "Fetching all clusters from Nirmata..."
echo "URL: ${NIRMATA_URL}"
echo "Environment ID: ${ENVIRONMENT_ID}"
echo "================================================"

# Get list of all clusters
clusters_response=$(curl -s -H "Authorization: NIRMATA-API ${API_TOKEN}" \
  "${NIRMATA_URL}/cluster/api/KubernetesCluster")

# Extract cluster IDs and names
cluster_data=$(echo "$clusters_response" | jq -r '.[] | "\(.id)|\(.name)"' 2>/dev/null)

if [ -z "$cluster_data" ]; then
  echo "Error: Could not fetch clusters or no clusters found"
  echo "Response: $clusters_response"
  exit 1
fi

# Create CSV header
echo "Cluster Name,Cluster ID,Kubeconfig API Server,Real API Server Endpoint,Has Localhost" > "${OUTPUT_FILE}"

echo "Found clusters. Processing..."
echo ""

# Process each cluster
while IFS='|' read -r cluster_id cluster_name; do
  if [ -z "$cluster_id" ] || [ "$cluster_id" = "null" ]; then
    continue
  fi
  
  total_clusters=$((total_clusters + 1))
  
  echo -n "[$total_clusters] Processing: ${cluster_name}..."
  
  # Fetch kubeconfig for this cluster
  kubeconfig=$(curl -s -H "Authorization: NIRMATA-API ${API_TOKEN}" \
    "${NIRMATA_URL}/environments/api/Root/${ENVIRONMENT_ID}/kubeconfig?clusterId=${cluster_id}")
  
  # Extract server URL from kubeconfig
  kubeconfig_server=$(echo "$kubeconfig" | jq -r '.yaml' 2>/dev/null | grep -i "server:" | head -1 | awk '{print $2}')
  
  # Fetch real endpoint from cluster config
  real_endpoint=$(curl -s -H "Authorization: NIRMATA-API ${API_TOKEN}" \
    "${NIRMATA_URL}/cluster/api/kubernetes/${cluster_id}/config" | jq -r '.[0].endpoint // "N/A"' 2>/dev/null)
  
  # Check if kubeconfig contains localhost
  has_localhost="No"
  if echo "$kubeconfig_server" | grep -qi "localhost"; then
    has_localhost="Yes"
    localhost_clusters=$((localhost_clusters + 1))
    echo " [LOCALHOST]"
  else
    echo " [Remote]"
  fi
  
  # Write to CSV (escape commas in values)
  echo "\"${cluster_name}\",\"${cluster_id}\",\"${kubeconfig_server}\",\"${real_endpoint}\",\"${has_localhost}\"" >> "${OUTPUT_FILE}"
  
done <<< "$cluster_data"

echo ""
echo "================================================"
echo "SUMMARY"
echo "================================================"
echo "Total clusters checked: ${total_clusters}"
echo "Clusters with localhost: ${localhost_clusters}"
echo "Clusters with remote URLs: $((total_clusters - localhost_clusters))"
echo ""
echo "Results saved to: ${OUTPUT_FILE}"

