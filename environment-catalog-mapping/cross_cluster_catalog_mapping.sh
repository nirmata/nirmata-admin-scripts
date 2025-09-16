#!/bin/bash

# Cross-Cluster Catalog to Environment Mapping Script
# Purpose: Map catalogs from source cluster environments to destination cluster environments
# Use case: After environment migration, manually link catalogs to new environments

# Check if all arguments are provided
if [ $# -ne 4 ]; then
    echo "Usage: $0 <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DESTINATION_CLUSTER>"
    echo ""
    echo "Example: $0 https://pe420.nirmata.co TOKEN n4k-rollout new-rhel"
    echo ""
    echo "This script will:"
    echo "  - Find environments in source cluster with their connected catalogs"
    echo "  - Find corresponding environments in destination cluster"
    echo "  - Generate mapping report for manual catalog linking"
    echo ""
    exit 1
fi

# API endpoint and token from command line arguments
API_ENDPOINT="$1"
API_TOKEN="$2"
SOURCE_CLUSTER="$3"
DESTINATION_CLUSTER="$4"

# Validate inputs
if [[ ! "$API_ENDPOINT" =~ ^https?:// ]]; then
    echo "Error: API_ENDPOINT must start with http:// or https://"
    exit 1
fi

if [ -z "$API_TOKEN" ]; then
    echo "Error: API_TOKEN cannot be empty"
    exit 1
fi

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Remove trailing slash from API_ENDPOINT if present
API_ENDPOINT="${API_ENDPOINT%/}"

# Create output filename
CSV_FILENAME="${SOURCE_CLUSTER}_to_${DESTINATION_CLUSTER}_catalog_mapping_$(date +%Y%m%d_%H%M%S).csv"

# Function to make API calls with error handling
make_api_call() {
    local method="$1"
    local url="$2"
    local description="$3"
    
    log_message "Making API call: $description" >&2
    local response=$(curl -s -w "%{http_code}" -X "$method" -H "Authorization: NIRMATA-API ${API_TOKEN}" -H "Accept: application/json" "$url")
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "$body"
        return 0
    else
        log_message "API call failed: $method $url - HTTP $http_code" >&2
        log_message "Response: $body" >&2
        if [ "$http_code" = "401" ]; then
            log_message "Authorization failed - please check your API token" >&2
        fi
        return 1
    fi
}

# Function to validate JSON response
validate_json() {
    local json="$1"
    if ! echo "$json" | jq empty 2>/dev/null; then
        log_message "Invalid JSON response received" >&2
        return 1
    fi
    return 0
}

log_message "Starting cross-cluster catalog mapping analysis"
log_message "Source Cluster: $SOURCE_CLUSTER → Destination Cluster: $DESTINATION_CLUSTER"
log_message "API Endpoint: $API_ENDPOINT"

# Create CSV header
echo "Source Environment,Source Env ID,Source Apps,Catalog Name,Catalog ID,Catalog Apps,Dest Environment,Dest Env ID,Dest Apps,Mapping Action,Manual Steps" > "$CSV_FILENAME"

# Get all clusters
log_message "Fetching cluster information..."
CLUSTERS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/clusters" "clusters")
if [ $? -ne 0 ] || ! validate_json "$CLUSTERS_RESPONSE"; then
    log_message "Failed to fetch clusters"
    exit 1
fi

# Find source and destination cluster IDs
SOURCE_CLUSTER_ID=$(echo "$CLUSTERS_RESPONSE" | jq -r ".[] | select(.name == \"$SOURCE_CLUSTER\") | .id")
DESTINATION_CLUSTER_ID=$(echo "$CLUSTERS_RESPONSE" | jq -r ".[] | select(.name == \"$DESTINATION_CLUSTER\") | .id")

if [ -z "$SOURCE_CLUSTER_ID" ] || [ "$SOURCE_CLUSTER_ID" = "null" ]; then
    log_message "Error: Source cluster '$SOURCE_CLUSTER' not found"
    echo "$CLUSTERS_RESPONSE" | jq -r '.[] | "Available: " + .name' >&2
    exit 1
fi

if [ -z "$DESTINATION_CLUSTER_ID" ] || [ "$DESTINATION_CLUSTER_ID" = "null" ]; then
    log_message "Error: Destination cluster '$DESTINATION_CLUSTER' not found"
    echo "$CLUSTERS_RESPONSE" | jq -r '.[] | "Available: " + .name' >&2
    exit 1
fi

log_message "Found source cluster ID: $SOURCE_CLUSTER_ID"
log_message "Found destination cluster ID: $DESTINATION_CLUSTER_ID"

# Get all environments
log_message "Fetching all environments..."
ENVIRONMENTS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/environments" "environments")
if [ $? -ne 0 ] || ! validate_json "$ENVIRONMENTS_RESPONSE"; then
    log_message "Failed to fetch environments"
    exit 1
fi

# Filter environments for source and destination clusters
SOURCE_ENVIRONMENTS=$(echo "$ENVIRONMENTS_RESPONSE" | jq -c ".[] | select(.cluster[0].id == \"$SOURCE_CLUSTER_ID\")")
DESTINATION_ENVIRONMENTS=$(echo "$ENVIRONMENTS_RESPONSE" | jq -c ".[] | select(.cluster[0].id == \"$DESTINATION_CLUSTER_ID\")")

if [ -z "$SOURCE_ENVIRONMENTS" ]; then
    log_message "No environments found for source cluster: $SOURCE_CLUSTER"
    exit 1
fi

if [ -z "$DESTINATION_ENVIRONMENTS" ]; then
    log_message "No environments found for destination cluster: $DESTINATION_CLUSTER"
    exit 1
fi

# Get all catalogs
log_message "Fetching catalog information..."
CATALOGS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/catalog/api/catalogs" "catalogs")
if [ $? -ne 0 ] || ! validate_json "$CATALOGS_RESPONSE"; then
    log_message "Failed to fetch catalogs"
    exit 1
fi

# Get all catalog applications
log_message "Fetching catalog applications..."
CATALOG_APPS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/catalog/api/applications" "catalog applications")
if [ $? -ne 0 ] || ! validate_json "$CATALOG_APPS_RESPONSE"; then
    log_message "Failed to fetch catalog applications"
    exit 1
fi

# Process each source environment
log_message "Processing source environments and finding catalog mappings..."

echo "$SOURCE_ENVIRONMENTS" | while IFS= read -r source_env; do
    SOURCE_ENV_NAME=$(echo "$source_env" | jq -r '.name')
    SOURCE_ENV_ID=$(echo "$source_env" | jq -r '.id')
    
    log_message "Processing source environment: $SOURCE_ENV_NAME"
    
    # Get applications in source environment
    SOURCE_APPS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/environments/${SOURCE_ENV_ID}/applications" "source environment applications")
    if [ $? -eq 0 ] && validate_json "$SOURCE_APPS_RESPONSE"; then
        SOURCE_APPS_COUNT=$(echo "$SOURCE_APPS_RESPONSE" | jq '. | length')
    else
        SOURCE_APPS_COUNT="N/A"
    fi
    
    # Skip environments with no applications
    if [ "$SOURCE_APPS_COUNT" = "0" ]; then
        log_message "  Skipping $SOURCE_ENV_NAME (no applications)"
        continue
    fi
    
    # Find corresponding destination environment
    # Remove cluster suffix and try different matching patterns
    SOURCE_BASE_NAME=$(echo "$SOURCE_ENV_NAME" | sed 's/-'"$SOURCE_CLUSTER"'$//')
    
    DEST_ENV_CANDIDATES=(
        "${SOURCE_BASE_NAME}-${DESTINATION_CLUSTER}"  # Replace cluster suffix
        "${SOURCE_BASE_NAME}"                         # Just base name
        "$SOURCE_ENV_NAME"                            # Exact name
    )
    
    DEST_ENV_NAME=""
    DEST_ENV_ID=""
    DEST_APPS_COUNT=""
    FOUND_DEST_ENV=false
    
    for candidate in "${DEST_ENV_CANDIDATES[@]}"; do
        DEST_MATCH=$(echo "$DESTINATION_ENVIRONMENTS" | jq -r "select(.name == \"$candidate\")")
        if [ -n "$DEST_MATCH" ] && [ "$DEST_MATCH" != "null" ]; then
            DEST_ENV_NAME=$(echo "$DEST_MATCH" | jq -r '.name')
            DEST_ENV_ID=$(echo "$DEST_MATCH" | jq -r '.id')
            
            # Get applications in destination environment
            DEST_APPS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/environments/${DEST_ENV_ID}/applications" "destination environment applications")
            if [ $? -eq 0 ] && validate_json "$DEST_APPS_RESPONSE"; then
                DEST_APPS_COUNT=$(echo "$DEST_APPS_RESPONSE" | jq '. | length')
            else
                DEST_APPS_COUNT="N/A"
            fi
            
            FOUND_DEST_ENV=true
            break
        fi
    done
    
    if [ "$FOUND_DEST_ENV" = false ]; then
        DEST_ENV_NAME="NOT_FOUND"
        DEST_ENV_ID="N/A"
        DEST_APPS_COUNT="N/A"
    fi
    
    # Find catalogs that might be connected to this source environment
    # Look for catalogs with similar names
    CATALOG_CANDIDATES=(
        "$SOURCE_BASE_NAME"                           # Base environment name
        "$(echo "$SOURCE_ENV_NAME" | sed 's/-'"$SOURCE_CLUSTER"'$//')"  # Remove cluster suffix
    )
    
    FOUND_CATALOGS=false
    
    for catalog_candidate in "${CATALOG_CANDIDATES[@]}"; do
        if [ -n "$catalog_candidate" ]; then
            CATALOG_MATCHES=$(echo "$CATALOGS_RESPONSE" | jq -c ".[] | select(.name == \"$catalog_candidate\")")
            
            if [ -n "$CATALOG_MATCHES" ]; then
                echo "$CATALOG_MATCHES" | while IFS= read -r catalog; do
                    CATALOG_NAME=$(echo "$catalog" | jq -r '.name')
                    CATALOG_ID=$(echo "$catalog" | jq -r '.id')
                    
                    # Count applications in this catalog
                    CATALOG_APPS_COUNT=$(echo "$CATALOG_APPS_RESPONSE" | jq "[.[] | select(.parent.id == \"$CATALOG_ID\")] | length")
                    
                    # Determine mapping action and manual steps
                    if [ "$FOUND_DEST_ENV" = true ]; then
                        MAPPING_ACTION="LINK_CATALOG"
                        MANUAL_STEPS="Use Catalog ID $CATALOG_ID to link to Dest Env ID $DEST_ENV_ID"
                    else
                        MAPPING_ACTION="CREATE_ENV_FIRST"
                        MANUAL_STEPS="Create destination environment '$SOURCE_BASE_NAME-$DESTINATION_CLUSTER' then link Catalog ID $CATALOG_ID"
                    fi
                    
                    # Write to CSV
                    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
                        "$SOURCE_ENV_NAME" "$SOURCE_ENV_ID" "$SOURCE_APPS_COUNT" \
                        "$CATALOG_NAME" "$CATALOG_ID" "$CATALOG_APPS_COUNT" \
                        "$DEST_ENV_NAME" "$DEST_ENV_ID" "$DEST_APPS_COUNT" \
                        "$MAPPING_ACTION" "$MANUAL_STEPS" >> "$CSV_FILENAME"
                    
                    log_message "  Found mapping: $SOURCE_ENV_NAME → $CATALOG_NAME → $DEST_ENV_NAME"
                    FOUND_CATALOGS=true
                done
            fi
        fi
    done
    
    # If no catalog found, still record the environment for manual review
    if [ "$FOUND_CATALOGS" = false ]; then
        if [ "$FOUND_DEST_ENV" = true ]; then
            MAPPING_ACTION="NO_CATALOG_FOUND"
            MANUAL_STEPS="No matching catalog found. Check if catalog exists or needs to be created for $SOURCE_BASE_NAME"
        else
            MAPPING_ACTION="NO_DEST_ENV_NO_CATALOG"
            MANUAL_STEPS="Create destination environment and find/create appropriate catalog"
        fi
        
        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "$SOURCE_ENV_NAME" "$SOURCE_ENV_ID" "$SOURCE_APPS_COUNT" \
            "N/A" "N/A" "N/A" \
            "$DEST_ENV_NAME" "$DEST_ENV_ID" "$DEST_APPS_COUNT" \
            "$MAPPING_ACTION" "$MANUAL_STEPS" >> "$CSV_FILENAME"
        
        log_message "  No catalog mapping found for: $SOURCE_ENV_NAME"
    fi
done

# Generate summary
log_message "Generating summary..."

TOTAL_MAPPINGS=$(tail -n +2 "$CSV_FILENAME" | wc -l | tr -d ' ')
LINK_CATALOG_COUNT=$(grep -c "LINK_CATALOG" "$CSV_FILENAME" || echo "0")
CREATE_ENV_FIRST_COUNT=$(grep -c "CREATE_ENV_FIRST" "$CSV_FILENAME" || echo "0")
NO_CATALOG_COUNT=$(grep -c "NO_CATALOG_FOUND" "$CSV_FILENAME" || echo "0")
NO_DEST_ENV_COUNT=$(grep -c "NO_DEST_ENV_NO_CATALOG" "$CSV_FILENAME" || echo "0")

# Create summary file
SUMMARY_FILE="${SOURCE_CLUSTER}_to_${DESTINATION_CLUSTER}_catalog_mapping_summary_$(date +%Y%m%d_%H%M%S).txt"

cat > "$SUMMARY_FILE" << EOF
Cross-Cluster Catalog Mapping Summary
====================================
Source Cluster: $SOURCE_CLUSTER
Destination Cluster: $DESTINATION_CLUSTER
Generated: $(date)
API Endpoint: $API_ENDPOINT

Summary Statistics:
------------------
Total Environment Mappings: $TOTAL_MAPPINGS
Ready to Link Catalog: $LINK_CATALOG_COUNT
Need to Create Dest Environment First: $CREATE_ENV_FIRST_COUNT
No Catalog Found: $NO_CATALOG_COUNT
No Destination Environment or Catalog: $NO_DEST_ENV_COUNT

Action Items:
------------
1. LINK_CATALOG: Use the Catalog ID and Dest Env ID to create manual links
2. CREATE_ENV_FIRST: Create the destination environment, then link catalog
3. NO_CATALOG_FOUND: Find or create appropriate catalogs for these environments
4. NO_DEST_ENV_NO_CATALOG: Complete manual setup required

Files Generated:
---------------
- Detailed mapping: $CSV_FILENAME
- Summary report: $SUMMARY_FILE

Manual Linking Steps:
-------------------
For LINK_CATALOG entries:
1. Use the Catalog ID from the CSV
2. Use the Dest Env ID from the CSV  
3. Create the catalog-to-environment link using Nirmata API or UI
4. Verify the link is established correctly

Example API Call for Manual Linking:
curl -X POST "${API_ENDPOINT}/catalog/api/catalogs/{CATALOG_ID}/environments" \\
  -H "Authorization: NIRMATA-API ${API_TOKEN}" \\
  -H "Content-Type: application/json" \\
  -d '{"environmentId": "{DEST_ENV_ID}"}'

EOF

log_message "Analysis complete!"
echo ""
echo "Cross-Cluster Catalog Mapping Summary:"
echo "======================================"
echo "Total Environment Mappings: $TOTAL_MAPPINGS"
echo "Ready to Link Catalog: $LINK_CATALOG_COUNT"
echo "Need to Create Dest Environment First: $CREATE_ENV_FIRST_COUNT"
echo "No Catalog Found: $NO_CATALOG_COUNT"
echo "No Destination Environment or Catalog: $NO_DEST_ENV_COUNT"
echo ""
echo "Files created:"
echo "- Detailed CSV: $CSV_FILENAME"
echo "- Summary report: $SUMMARY_FILE"
echo ""
echo "Next Steps:"
echo "1. Open the CSV file to see specific Catalog IDs and Environment IDs"
echo "2. Use the Manual Steps column for each mapping action"
echo "3. Focus on 'LINK_CATALOG' entries - these are ready for immediate linking"
