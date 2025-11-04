#!/bin/bash

# Environment to Catalog Mapping Script
# This script lists all environments in a cluster with their mapped catalogs
# Helps identify which environments have catalog applications for manual mapping

# Check if all arguments are provided - support both same-env and cross-env scenarios
if [ $# -lt 3 ] || [ $# -gt 6 ]; then
    echo "Usage: $0 <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> [DEST_CLUSTER] [DEST_API_ENDPOINT] [DEST_API_TOKEN]"
    echo ""
    echo "Same Environment (Single API):"
    echo "  $0 https://pe420.nirmata.co API_TOKEN source-cluster dest-cluster"
    echo ""
    echo "Cross Environment (Different APIs):"
    echo "  $0 https://source.nirmata.co SOURCE_TOKEN source-cluster dest-cluster https://dest.nirmata.co DEST_TOKEN"
    echo ""
    echo "Single Cluster Analysis:"
    echo "  $0 https://pe420.nirmata.co API_TOKEN cluster-name"
    echo ""
    echo "This script will:"
    echo "  - List all environments in the source cluster"
    echo "  - Show existing catalogs that could map to source environments"
    echo "  - If destination cluster provided, analyze destination environments"
    echo "  - Generate a CSV report for manual catalog mapping"
    echo ""
    echo "Modes:"
    echo "  1. Single cluster: Analyze environments vs catalogs in same system"
    echo "  2. Same-env cross-cluster: Map between clusters in same Nirmata instance"
    echo "  3. Cross-env: Map between clusters in different Nirmata instances"
    echo ""
    exit 1
fi

# Parse arguments based on number provided
API_ENDPOINT="$1"
API_TOKEN="$2"
SOURCE_CLUSTER="$3"

# Determine operation mode based on arguments
if [ $# -eq 3 ]; then
    # Single cluster mode
    OPERATION_MODE="single-cluster"
    DESTINATION_CLUSTER=""
    DEST_API_ENDPOINT=""
    DEST_API_TOKEN=""
elif [ $# -eq 4 ]; then
    # Same environment, cross-cluster mode
    OPERATION_MODE="same-env-cross-cluster"
    DESTINATION_CLUSTER="$4"
    DEST_API_ENDPOINT="$API_ENDPOINT"
    DEST_API_TOKEN="$API_TOKEN"
elif [ $# -eq 6 ]; then
    # Cross environment mode
    OPERATION_MODE="cross-env"
    DESTINATION_CLUSTER="$4"
    DEST_API_ENDPOINT="$5"
    DEST_API_TOKEN="$6"
else
    echo "Error: Invalid number of arguments"
    exit 1
fi

# Validate API_ENDPOINT format
if [[ ! "$API_ENDPOINT" =~ ^https?:// ]]; then
    echo "Error: API_ENDPOINT must start with http:// or https://"
    exit 1
fi

# Validate API_TOKEN is not empty
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

# Create appropriate filename based on operation mode
case "$OPERATION_MODE" in
    "single-cluster")
        CSV_FILENAME="${SOURCE_CLUSTER}_environment_catalog_mapping_$(date +%Y%m%d_%H%M%S).csv"
        log_message "Running in single-cluster mode: $SOURCE_CLUSTER"
        ;;
    "same-env-cross-cluster")
        CSV_FILENAME="${SOURCE_CLUSTER}_to_${DESTINATION_CLUSTER}_env_catalog_mapping_$(date +%Y%m%d_%H%M%S).csv"
        log_message "Running in same-env cross-cluster mode: $SOURCE_CLUSTER → $DESTINATION_CLUSTER"
        ;;
    "cross-env")
        CSV_FILENAME="${SOURCE_CLUSTER}_to_${DESTINATION_CLUSTER}_cross_env_mapping_$(date +%Y%m%d_%H%M%S).csv"
        log_message "Running in cross-environment mode: $SOURCE_CLUSTER → $DESTINATION_CLUSTER"
        ;;
esac

# Function to make API calls with error handling
make_api_call() {
    local method="$1"
    local url="$2"
    local token="$3"
    local description="$4"
    
    log_message "Making API call: $description" >&2
    local response=$(curl -s -w "%{http_code}" -X "$method" -H "Authorization: NIRMATA-API ${token}" -H "Accept: application/json" "$url")
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

# Function to make destination API calls (for cross-env scenarios)
make_dest_api_call() {
    local method="$1"
    local url="$2"
    local description="$3"
    
    make_api_call "$method" "$url" "$DEST_API_TOKEN" "$description"
}

# Function to validate JSON response
validate_json() {
    local json="$1"
    if ! echo "$json" | jq empty 2>/dev/null; then
        log_message "Invalid JSON response received"
        log_message "Response was: $json"
        return 1
    fi
    return 0
}

log_message "Starting environment to catalog mapping analysis"
log_message "API Endpoint: $API_ENDPOINT"
log_message "Operation Mode: $OPERATION_MODE"

# Create CSV header based on operation mode
case "$OPERATION_MODE" in
    "single-cluster")
        echo "Environment Name,Environment ID,Applications Count,Catalog Name,Catalog ID,Catalog Apps Count,Mapping Status,Notes" > "$CSV_FILENAME"
        ;;
    "same-env-cross-cluster"|"cross-env")
        echo "Source Environment,Source Env ID,Source Apps Count,Dest Environment,Dest Env ID,Dest Apps Count,Catalog Name,Catalog ID,Catalog Apps Count,Mapping Status,Recommendations" > "$CSV_FILENAME"
        ;;
esac

# Get all clusters to find the source and destination cluster IDs
log_message "Fetching cluster information..."
CLUSTERS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/clusters" "$API_TOKEN" "source clusters")
if [ $? -ne 0 ]; then
    log_message "Failed to fetch clusters"
    exit 1
fi

if ! validate_json "$CLUSTERS_RESPONSE"; then
    exit 1
fi

# Find the source cluster ID
SOURCE_CLUSTER_ID=$(echo "$CLUSTERS_RESPONSE" | jq -r ".[] | select(.name == \"$SOURCE_CLUSTER\") | .id")

if [ -z "$SOURCE_CLUSTER_ID" ] || [ "$SOURCE_CLUSTER_ID" = "null" ]; then
    log_message "Error: Source cluster '$SOURCE_CLUSTER' not found"
    log_message "Available clusters:"
    echo "$CLUSTERS_RESPONSE" | jq -r '.[] | "  - " + .name'
    exit 1
fi

log_message "Found source cluster ID: $SOURCE_CLUSTER_ID"

# Find the destination cluster ID if specified
DESTINATION_CLUSTER_ID=""
if [ -n "$DESTINATION_CLUSTER" ]; then
    DESTINATION_CLUSTER_ID=$(echo "$CLUSTERS_RESPONSE" | jq -r ".[] | select(.name == \"$DESTINATION_CLUSTER\") | .id")
    
    if [ -z "$DESTINATION_CLUSTER_ID" ] || [ "$DESTINATION_CLUSTER_ID" = "null" ]; then
        log_message "Error: Destination cluster '$DESTINATION_CLUSTER' not found"
        log_message "Available clusters:"
        echo "$CLUSTERS_RESPONSE" | jq -r '.[] | "  - " + .name'
        exit 1
    fi
    
    log_message "Found destination cluster ID: $DESTINATION_CLUSTER_ID"
fi

# Get all environments
log_message "Fetching all environments..."
ENVIRONMENTS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/environments" "$API_TOKEN" "source environments")
if [ $? -ne 0 ]; then
    log_message "Failed to fetch environments"
    exit 1
fi

if ! validate_json "$ENVIRONMENTS_RESPONSE"; then
    exit 1
fi

# Filter environments for the source cluster
SOURCE_ENVIRONMENTS=$(echo "$ENVIRONMENTS_RESPONSE" | jq -c ".[] | select(.cluster[0].id == \"$SOURCE_CLUSTER_ID\")")

if [ -z "$SOURCE_ENVIRONMENTS" ]; then
    log_message "No environments found for source cluster: $SOURCE_CLUSTER"
    exit 1
fi

# Filter environments for the destination cluster if specified
DESTINATION_ENVIRONMENTS=""
if [ -n "$DESTINATION_CLUSTER_ID" ]; then
    DESTINATION_ENVIRONMENTS=$(echo "$ENVIRONMENTS_RESPONSE" | jq -c ".[] | select(.cluster[0].id == \"$DESTINATION_CLUSTER_ID\")")
    
    if [ -z "$DESTINATION_ENVIRONMENTS" ]; then
        log_message "No environments found for destination cluster: $DESTINATION_CLUSTER"
        exit 1
    fi
fi

# Get all catalogs
log_message "Fetching catalog information..."
CATALOGS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/catalog/api/catalogs" "$API_TOKEN" "catalogs")
if [ $? -ne 0 ]; then
    log_message "Failed to fetch catalogs"
    exit 1
fi

if ! validate_json "$CATALOGS_RESPONSE"; then
    exit 1
fi

# Get all catalog applications
log_message "Fetching catalog applications..."
CATALOG_APPS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/catalog/api/applications" "$API_TOKEN" "catalog applications")
if [ $? -ne 0 ]; then
    log_message "Failed to fetch catalog applications"
    exit 1
fi

if ! validate_json "$CATALOG_APPS_RESPONSE"; then
    exit 1
fi

# Process environments based on operation mode
log_message "Processing environments and their catalog mappings..."

if [ "$OPERATION_MODE" = "cross-cluster" ]; then
    # Cross-cluster mode: map source environments to destination environments and catalogs
    log_message "Cross-cluster mapping: $SOURCE_CLUSTER → $DESTINATION_CLUSTER"
    
    echo "$SOURCE_ENVIRONMENTS" | while IFS= read -r source_env; do
        SOURCE_ENV_NAME=$(echo "$source_env" | jq -r '.name')
        SOURCE_ENV_ID=$(echo "$source_env" | jq -r '.id')
        
        log_message "Processing source environment: $SOURCE_ENV_NAME"
        
        # Get applications in source environment
        SOURCE_APPS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/environments/${SOURCE_ENV_ID}/applications" "$API_TOKEN" "source environment applications")
        if [ $? -eq 0 ] && validate_json "$SOURCE_APPS_RESPONSE"; then
            SOURCE_APPS_COUNT=$(echo "$SOURCE_APPS_RESPONSE" | jq '. | length')
        else
            SOURCE_APPS_COUNT="N/A"
        fi
        
        # Look for corresponding destination environment
        SOURCE_BASE_NAME=$(echo "$SOURCE_ENV_NAME" | sed 's/-'"$SOURCE_CLUSTER"'$//' | sed 's/-[0-9].*$//')
        
        DEST_ENV_NAME=""
        DEST_ENV_ID=""
        DEST_APPS_COUNT=""
        MAPPING_STATUS=""
        RECOMMENDATIONS=""
        
        # Try to find matching destination environment
        DEST_ENV_CANDIDATES=(
            "${SOURCE_BASE_NAME}-${DESTINATION_CLUSTER}"
            "${SOURCE_BASE_NAME}"
            "$SOURCE_ENV_NAME"
        )
        
        FOUND_DEST_ENV=false
        for candidate in "${DEST_ENV_CANDIDATES[@]}"; do
            DEST_MATCH=$(echo "$DESTINATION_ENVIRONMENTS" | jq -r "select(.name == \"$candidate\")")
            if [ -n "$DEST_MATCH" ] && [ "$DEST_MATCH" != "null" ]; then
                DEST_ENV_NAME=$(echo "$DEST_MATCH" | jq -r '.name')
                DEST_ENV_ID=$(echo "$DEST_MATCH" | jq -r '.id')
                
                # Get applications in destination environment
                DEST_APPS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/environments/${DEST_ENV_ID}/applications" "$API_TOKEN" "destination environment applications")
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
            DEST_ENV_NAME="Not Found"
            DEST_ENV_ID="N/A"
            DEST_APPS_COUNT="N/A"
        fi
        
        # Look for matching catalog
        CATALOG_CANDIDATES=(
            "$SOURCE_BASE_NAME"
            "$DEST_ENV_NAME"
            "$(echo "$SOURCE_ENV_NAME" | sed 's/-'"$SOURCE_CLUSTER"'$//')"
        )
        
        CATALOG_NAME=""
        CATALOG_ID=""
        CATALOG_APPS_COUNT=""
        FOUND_CATALOG=false
        
        for catalog_candidate in "${CATALOG_CANDIDATES[@]}"; do
            if [ -n "$catalog_candidate" ] && [ "$catalog_candidate" != "Not Found" ] && [ "$catalog_candidate" != "N/A" ]; then
                CATALOG_MATCH=$(echo "$CATALOGS_RESPONSE" | jq -r ".[] | select(.name == \"$catalog_candidate\")")
                
                if [ -n "$CATALOG_MATCH" ] && [ "$CATALOG_MATCH" != "null" ]; then
                    CATALOG_NAME=$(echo "$CATALOG_MATCH" | jq -r '.name')
                    CATALOG_ID=$(echo "$CATALOG_MATCH" | jq -r '.id')
                    
                    # Count applications in this catalog
                    CATALOG_APPS_COUNT=$(echo "$CATALOG_APPS_RESPONSE" | jq "[.[] | select(.parent.id == \"$CATALOG_ID\")] | length")
                    
                    FOUND_CATALOG=true
                    break
                fi
            fi
        done
        
        if [ "$FOUND_CATALOG" = false ]; then
            CATALOG_NAME="N/A"
            CATALOG_ID="N/A"
            CATALOG_APPS_COUNT="N/A"
        fi
        
        # Determine mapping status and recommendations
        if [ "$FOUND_DEST_ENV" = true ] && [ "$FOUND_CATALOG" = true ]; then
            MAPPING_STATUS="Ready for Migration"
            RECOMMENDATIONS="Source env → Dest env → Catalog mapping available"
        elif [ "$FOUND_DEST_ENV" = true ] && [ "$FOUND_CATALOG" = false ]; then
            MAPPING_STATUS="Create Catalog"
            RECOMMENDATIONS="Destination environment exists, create catalog for applications"
        elif [ "$FOUND_DEST_ENV" = false ] && [ "$FOUND_CATALOG" = true ]; then
            MAPPING_STATUS="Create Environment"
            RECOMMENDATIONS="Catalog exists, create destination environment"
        else
            MAPPING_STATUS="Manual Setup Required"
            RECOMMENDATIONS="Create both destination environment and catalog"
        fi
        
        # Write to CSV
        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "$SOURCE_ENV_NAME" "$SOURCE_ENV_ID" "$SOURCE_APPS_COUNT" \
            "$DEST_ENV_NAME" "$DEST_ENV_ID" "$DEST_APPS_COUNT" \
            "$CATALOG_NAME" "$CATALOG_ID" "$CATALOG_APPS_COUNT" \
            "$MAPPING_STATUS" "$RECOMMENDATIONS" >> "$CSV_FILENAME"
        
        log_message "  Source: $SOURCE_ENV_NAME → Dest: $DEST_ENV_NAME → Catalog: $CATALOG_NAME | Status: $MAPPING_STATUS"
    done
    
else
    # Single-cluster mode: map environments to existing catalogs
    log_message "Single-cluster mapping for: $SOURCE_CLUSTER"
    
    echo "$SOURCE_ENVIRONMENTS" | while IFS= read -r env; do
        ENV_NAME=$(echo "$env" | jq -r '.name')
        ENV_ID=$(echo "$env" | jq -r '.id')
        
        log_message "Processing environment: $ENV_NAME"
        
        # Get applications in this environment
        ENV_APPS_RESPONSE=$(make_api_call "GET" "${API_ENDPOINT}/environments/api/environments/${ENV_ID}/applications" "$API_TOKEN" "environment applications")
        if [ $? -eq 0 ] && validate_json "$ENV_APPS_RESPONSE"; then
            ENV_APPS_COUNT=$(echo "$ENV_APPS_RESPONSE" | jq '. | length')
        else
            ENV_APPS_COUNT="N/A"
        fi
        
        # Look for matching catalogs (by name similarity)
        POSSIBLE_CATALOG_NAMES=(
            "$ENV_NAME"                                    # Exact match
            "$(echo "$ENV_NAME" | sed 's/-[0-9].*$//')"   # Remove cluster suffix
            "$(echo "$ENV_NAME" | sed 's/-'"$SOURCE_CLUSTER"'$//')" # Remove specific cluster name
        )
        
        FOUND_CATALOG=false
        CATALOG_NAME=""
        CATALOG_ID=""
        CATALOG_APPS_COUNT=""
        MAPPING_STATUS=""
        NOTES=""
        
        # Check each possible catalog name
        for possible_name in "${POSSIBLE_CATALOG_NAMES[@]}"; do
            if [ -n "$possible_name" ] && [ "$possible_name" != "$ENV_NAME" ] || [ "$possible_name" = "$ENV_NAME" ]; then
                CATALOG_MATCH=$(echo "$CATALOGS_RESPONSE" | jq -r ".[] | select(.name == \"$possible_name\")")
                
                if [ -n "$CATALOG_MATCH" ] && [ "$CATALOG_MATCH" != "null" ]; then
                    CATALOG_NAME=$(echo "$CATALOG_MATCH" | jq -r '.name')
                    CATALOG_ID=$(echo "$CATALOG_MATCH" | jq -r '.id')
                    
                    # Count applications in this catalog
                    CATALOG_APPS_COUNT=$(echo "$CATALOG_APPS_RESPONSE" | jq "[.[] | select(.parent.id == \"$CATALOG_ID\")] | length")
                    
                    if [ "$possible_name" = "$ENV_NAME" ]; then
                        MAPPING_STATUS="Exact Match"
                        NOTES="Environment name matches catalog name exactly"
                    else
                        MAPPING_STATUS="Potential Match"
                        NOTES="Environment name similar to catalog name (${possible_name})"
                    fi
                    
                    FOUND_CATALOG=true
                    break
                fi
            fi
        done
        
        # If no catalog found, check for partial matches
        if [ "$FOUND_CATALOG" = false ]; then
            # Look for catalogs that contain part of the environment name
            ENV_BASE=$(echo "$ENV_NAME" | sed 's/-'"$SOURCE_CLUSTER"'$//' | sed 's/-[0-9].*$//')
            
            if [ ${#ENV_BASE} -gt 3 ]; then  # Only search if base name is meaningful
                PARTIAL_MATCHES=$(echo "$CATALOGS_RESPONSE" | jq -r ".[] | select(.name | contains(\"$ENV_BASE\")) | .name")
                
                if [ -n "$PARTIAL_MATCHES" ]; then
                    MAPPING_STATUS="Needs Review"
                    NOTES="Possible matches found: $(echo "$PARTIAL_MATCHES" | tr '\n' ',' | sed 's/,$//')"
                else
                    MAPPING_STATUS="No Match"
                    NOTES="No matching catalog found"
                fi
            else
                MAPPING_STATUS="No Match"
                NOTES="No matching catalog found"
            fi
            
            CATALOG_NAME="N/A"
            CATALOG_ID="N/A"
            CATALOG_APPS_COUNT="N/A"
        fi
        
        # Write to CSV
        printf "%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "$ENV_NAME" "$ENV_ID" "$ENV_APPS_COUNT" "$CATALOG_NAME" "$CATALOG_ID" "$CATALOG_APPS_COUNT" "$MAPPING_STATUS" "$NOTES" >> "$CSV_FILENAME"
        
        log_message "  Environment: $ENV_NAME | Apps: $ENV_APPS_COUNT | Catalog: $CATALOG_NAME | Status: $MAPPING_STATUS"
    done
fi

# Generate summary information
log_message "Generating summary information..."

# Count environments by mapping status
TOTAL_ENVS=$(wc -l < "$CSV_FILENAME" | tr -d ' ')
TOTAL_ENVS=$((TOTAL_ENVS - 1))  # Subtract header

EXACT_MATCHES=$(grep -c "Exact Match" "$CSV_FILENAME" || echo "0")
POTENTIAL_MATCHES=$(grep -c "Potential Match" "$CSV_FILENAME" || echo "0")
NEEDS_REVIEW=$(grep -c "Needs Review" "$CSV_FILENAME" || echo "0")
NO_MATCHES=$(grep -c "No Match" "$CSV_FILENAME" || echo "0")

# Create summary file
SUMMARY_FILE="${TARGET_CLUSTER}_catalog_mapping_summary_$(date +%Y%m%d_%H%M%S).txt"

cat > "$SUMMARY_FILE" << EOF
Environment to Catalog Mapping Summary
=====================================
Cluster: $TARGET_CLUSTER
Generated: $(date)
API Endpoint: $API_ENDPOINT

Summary Statistics:
------------------
Total Environments: $TOTAL_ENVS
Exact Matches: $EXACT_MATCHES
Potential Matches: $POTENTIAL_MATCHES
Needs Review: $NEEDS_REVIEW
No Matches: $NO_MATCHES

Recommendations:
---------------
1. Review environments with "Exact Match" status - these can be mapped automatically
2. Verify environments with "Potential Match" status - may need minor adjustments
3. Manually review environments with "Needs Review" status
4. Create new catalogs for environments with "No Match" status if needed

Files Generated:
---------------
- Detailed mapping: $CSV_FILENAME
- Summary report: $SUMMARY_FILE

Next Steps:
----------
1. Open the CSV file in Excel/spreadsheet application
2. Review the mapping status for each environment
3. For manual mapping, use the Environment ID and Catalog ID columns
4. Consider running the migration scripts for environments with clear matches

EOF

# Display summary
log_message "Analysis complete!"
echo ""
echo "Summary:"
echo "=========="
echo "Total Environments: $TOTAL_ENVS"
echo "Exact Matches: $EXACT_MATCHES"
echo "Potential Matches: $POTENTIAL_MATCHES"
echo "Needs Review: $NEEDS_REVIEW"
echo "No Matches: $NO_MATCHES"
echo ""
echo "Files created:"
echo "- Detailed CSV: $CSV_FILENAME"
echo "- Summary report: $SUMMARY_FILE"
echo ""
echo "You can now:"
echo "1. Open the CSV file to review environment-catalog mappings"
echo "2. Use the Environment ID and Catalog ID for manual mapping"
echo "3. Run migration scripts for environments with clear catalog matches"
