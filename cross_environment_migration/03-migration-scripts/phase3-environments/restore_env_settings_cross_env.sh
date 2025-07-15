#!/bin/bash

# Check if required parameters are provided
if [ "$#" -lt 6 ]; then
    echo "Usage: $0 <source_api_endpoint> <source_token> <source_cluster> <dest_api_endpoint> <dest_token> <dest_cluster> [OPTIONS]"
    echo ""
    echo "Safety Options:"
    echo "  --dry-run                    Show what would be done without making changes (DEFAULT)"
    echo "  --generate-mapping           Generate environment mapping file for review"
    echo "  --use-mapping-file FILE      Use pre-verified mapping file for migration"
    echo "  --live                       Make actual changes (requires mapping file)"
    echo "  --auto-confirm              Skip confirmation prompts (use with extreme caution)"
    echo "  --interactive               Interactive mode - confirm each environment mapping"
    echo ""
    echo "🛡️  ULTRA-SAFE WORKFLOW (RECOMMENDED):"
    echo "  1. $0 ... --generate-mapping     # Generate mapping file"
    echo "  2. Review and edit mapping file   # Manual verification"
    echo "  3. $0 ... --use-mapping-file mapping.json --live  # Execute verified mappings"
    echo ""
    echo "🤝  INTERACTIVE WORKFLOW:"
    echo "  $0 ... --interactive --live      # Confirm each environment mapping manually"
    echo ""
    echo "Examples:"
    echo "  # Step 1: Generate mapping file (SAFE)"
    echo "  $0 https://source.co TOKEN1 source-cluster https://dest.co TOKEN2 dest-cluster --generate-mapping"
    echo ""
    echo "  # Step 2: Execute with verified mapping (CONTROLLED)"
    echo "  $0 https://source.co TOKEN1 source-cluster https://dest.co TOKEN2 dest-cluster --use-mapping-file verified_mapping.json --live"
    exit 1
fi

SOURCE_API_ENDPOINT=$1
SOURCE_TOKEN=$2
SOURCE_CLUSTER=$3
DEST_API_ENDPOINT=$4
DEST_TOKEN=$5
DEST_CLUSTER=$6

# Parse safety flags
DRY_RUN=true
AUTO_CONFIRM=false
GENERATE_MAPPING=false
USE_MAPPING_FILE=""
LIVE_MODE=false
INTERACTIVE_MODE=false

shift 6
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            LIVE_MODE=false
            shift
            ;;
        --generate-mapping)
            GENERATE_MAPPING=true
            DRY_RUN=true
            shift
            ;;
        --use-mapping-file)
            USE_MAPPING_FILE="$2"
            if [ ! -f "$USE_MAPPING_FILE" ]; then
                echo "❌ Error: Mapping file '$USE_MAPPING_FILE' not found"
                exit 1
            fi
            shift 2
            ;;
        --live)
            LIVE_MODE=true
            DRY_RUN=false
            shift
            ;;
        --auto-confirm)
            AUTO_CONFIRM=true
            shift
            ;;
        --interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Safety validation
if [ "$LIVE_MODE" = true ] && [ -z "$USE_MAPPING_FILE" ] && [ "$AUTO_CONFIRM" != true ] && [ "$INTERACTIVE_MODE" != true ]; then
    echo "❌ ERROR: Live mode requires one of:"
    echo "  --use-mapping-file FILE    (use pre-verified mapping file)"
    echo "  --auto-confirm             (automatic execution, no prompts)"
    echo "  --interactive              (manual confirmation of each mapping)"
    echo "🛡️  Please choose one of the above safety options"
    exit 1
fi

# Create logs directory if it doesn't exist
LOG_DIR="logs"
mkdir -p "$LOG_DIR"

# Create timestamp for consistent naming
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Create log file with timestamp and safety mode indicator
if [ "$DRY_RUN" = true ]; then
    if [ "$INTERACTIVE_MODE" = true ]; then
        LOG_FILE="${LOG_DIR}/env_restore_DRY_RUN_INTERACTIVE_${TIMESTAMP}.log"
        SUMMARY_FILE="${LOG_DIR}/env_restore_summary_DRY_RUN_INTERACTIVE_${TIMESTAMP}.log"
        MAPPING_FILE="${LOG_DIR}/env_mapping_preview_DRY_RUN_INTERACTIVE_${TIMESTAMP}.json"
    else
        LOG_FILE="${LOG_DIR}/env_restore_DRY_RUN_${TIMESTAMP}.log"
        SUMMARY_FILE="${LOG_DIR}/env_restore_summary_DRY_RUN_${TIMESTAMP}.log"
        MAPPING_FILE="${LOG_DIR}/env_mapping_preview_DRY_RUN_${TIMESTAMP}.json"
    fi
else
    if [ "$INTERACTIVE_MODE" = true ]; then
        LOG_FILE="${LOG_DIR}/env_restore_LIVE_INTERACTIVE_${TIMESTAMP}.log"
        SUMMARY_FILE="${LOG_DIR}/env_restore_summary_LIVE_INTERACTIVE_${TIMESTAMP}.log"
        MAPPING_FILE="${LOG_DIR}/env_mapping_confirmed_LIVE_INTERACTIVE_${TIMESTAMP}.json"
    else
        LOG_FILE="${LOG_DIR}/env_restore_LIVE_${TIMESTAMP}.log"
        SUMMARY_FILE="${LOG_DIR}/env_restore_summary_LIVE_${TIMESTAMP}.log"
        MAPPING_FILE="${LOG_DIR}/env_mapping_confirmed_LIVE_${TIMESTAMP}.json"
    fi
fi

# Function to log messages with timestamp and safety indicator
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    if [ "$DRY_RUN" = true ]; then
        echo "🔍 [DRY-RUN] $message"
        echo "[DRY-RUN] $message" >> "$LOG_FILE"
    else
        echo "$message"
        echo "$message" >> "$LOG_FILE"
    fi
}

# Function to log summary with safety indicator
log_summary() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $message" >> "$SUMMARY_FILE"
    else
        echo "$message" >> "$SUMMARY_FILE"
    fi
}

# Function to validate JSON response
validate_json_response() {
    local response="$1"
    local api_name="$2"
    
    if [ -z "$response" ]; then
        log_message "ERROR: Empty response from $api_name API"
        return 1
    fi
    
    if echo "$response" | grep -q "Not authorized"; then
        log_message "ERROR: Not authorized for $api_name API"
        return 1
    fi
    
    if echo "$response" | grep -q -i "error"; then
        log_message "ERROR: API error from $api_name: $response"
        return 1
    fi
    
    if ! echo "$response" | jq '.' >/dev/null 2>&1; then
        log_message "ERROR: Invalid JSON response from $api_name API"
        log_message "Response: $response"
        return 1
    fi
    
    return 0
}

# Function to make API call with error handling
make_api_call() {
    local method="$1"
    local url="$2"
    local token="$3"
    local data="$4"
    local api_name="$5"
    
    local response
    local http_code
    
    if [ -z "$data" ]; then
        # GET request
        response=$(curl -s -w "\n%{http_code}" -H "Accept: application/json" \
            -H "Authorization: NIRMATA-API $token" \
            "$url")
    else
        # POST/PUT request with data
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -H "Authorization: NIRMATA-API $token" \
            -d "$data" \
            "$url")
    fi
    
    # Extract HTTP code from last line
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    
    # Check HTTP status
    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
        log_message "ERROR: HTTP $http_code from $api_name API"
        log_message "Response: $response"
        return 1
    fi
    
    # Validate JSON
    if ! validate_json_response "$response" "$api_name"; then
        return 1
    fi
    
    echo "$response"
    return 0
}

# Function to safely extract JSON field
safe_json_extract() {
    local json="$1"
    local field="$2"
    local default_value="$3"
    
    local result
    result=$(echo "$json" | jq -r "$field" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$result" ] || [ "$result" = "null" ]; then
        echo "$default_value"
    else
        echo "$result"
    fi
}

# Function to save environment mappings to JSON file
save_environment_mappings() {
    local mapping_file="$1"
    local mode="$2"
    
    log_message "Saving environment mappings to: $mapping_file"
    
    # Create JSON structure using echo instead of HERE documents to avoid expansion issues
    echo "{" > "$mapping_file"
    echo "  \"migration_info\": {" >> "$mapping_file"
    echo "    \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"," >> "$mapping_file"
    echo "    \"mode\": \"$mode\"," >> "$mapping_file"
    echo "    \"source_cluster\": \"$SOURCE_CLUSTER\"," >> "$mapping_file"
    echo "    \"source_endpoint\": \"$SOURCE_API_ENDPOINT\"," >> "$mapping_file"
    echo "    \"destination_cluster\": \"$DEST_CLUSTER\"," >> "$mapping_file"
    echo "    \"destination_endpoint\": \"$DEST_API_ENDPOINT\"," >> "$mapping_file"
    echo "    \"total_environments\": ${#MAPPING_PREVIEW[@]}," >> "$mapping_file"
    echo "    \"failed_mappings\": ${#MAPPING_ERRORS[@]}" >> "$mapping_file"
    echo "  }," >> "$mapping_file"
    echo "  \"successful_mappings\": [" >> "$mapping_file"

    # Add successful mappings
    local first=true
    for mapping in "${MAPPING_PREVIEW[@]}"; do
        IFS='|' read -r source_env dest_env <<< "$mapping"
        
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$mapping_file"
        fi
        
        echo "    {" >> "$mapping_file"
        echo "      \"source_environment\": \"$source_env\"," >> "$mapping_file"
        echo "      \"destination_environment\": \"$dest_env\"," >> "$mapping_file"
        echo "      \"status\": \"mapped\"" >> "$mapping_file"
        echo -n "    }" >> "$mapping_file"
    done
    
    echo "" >> "$mapping_file"
    echo "  ]," >> "$mapping_file"
    echo "  \"failed_mappings\": [" >> "$mapping_file"

    # Add failed mappings
    first=true
    for error_env in "${MAPPING_ERRORS[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$mapping_file"
        fi
        
        echo "    {" >> "$mapping_file"
        echo "      \"source_environment\": \"$error_env\"," >> "$mapping_file"
        echo "      \"destination_environment\": null," >> "$mapping_file"
        echo "      \"status\": \"no_match_found\"" >> "$mapping_file"
        echo -n "    }" >> "$mapping_file"
    done
    
    echo "" >> "$mapping_file"
    echo "  ]" >> "$mapping_file"
    echo "}" >> "$mapping_file"

    log_message "Environment mappings saved to: $mapping_file"
}

# Function to interactively confirm environment mapping
interactive_confirm_mapping() {
    local source_env_name="$1"
    local suggested_dest_env_name="$2"
    
    echo ""
    echo "🔍 ENVIRONMENT MAPPING CONFIRMATION"
    echo "======================================"
    echo "Source Environment: $source_env_name"
    echo "Suggested Destination: $suggested_dest_env_name"
    echo ""
    
    while true; do
        echo -n "Do you want to copy settings from '$source_env_name' to '$suggested_dest_env_name'? (y/n/list): "
        read -r response
        
        # Debug: Show what was entered
        echo "DEBUG: You entered: '$response'"
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]|"y"|"Y")
                echo "✅ Confirmed: $source_env_name → $suggested_dest_env_name"
                echo "$suggested_dest_env_name"
                return 0
                ;;
            [Nn]|[Nn][Oo]|"n"|"N")
                echo ""
                echo "❌ Mapping rejected. Please specify the correct destination environment."
                echo ""
                echo "Available destination environments:"
                echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" '.[] | select(.cluster[].id == $cluster) | "  - " + .name' | sort
                echo ""
                
                while true; do
                    echo -n "Enter the correct destination environment name (or 'skip' to skip this environment): "
                    read -r custom_dest_name
                    
                    echo "DEBUG: You entered custom name: '$custom_dest_name'"
                    
                    if [ "$custom_dest_name" = "skip" ]; then
                        echo "⏭️  Skipping environment: $source_env_name"
                        return 1
                    fi
                    
                    # Validate the custom destination environment exists
                    local custom_dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$custom_dest_name" '.[] | select(.cluster[].id == $cluster and .name == $name)')
                    
                    if [ ! -z "$custom_dest_env" ] && [ "$custom_dest_env" != "null" ]; then
                        echo "✅ Custom mapping confirmed: $source_env_name → $custom_dest_name"
                        echo "$custom_dest_name"
                        return 0
                    else
                        echo "❌ Error: Destination environment '$custom_dest_name' not found in cluster '$DEST_CLUSTER'"
                        echo "Please choose from the available environments listed above."
                        echo ""
                    fi
                done
                ;;
            [Ll][Ii][Ss][Tt]|"list"|"LIST")
                echo ""
                echo "📋 Available destination environments in cluster '$DEST_CLUSTER':"
                echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" '.[] | select(.cluster[].id == $cluster) | "  - " + .name' | sort
                echo ""
                # Continue the loop to ask again
                ;;
            "")
                echo "Please enter a response. Options: 'y' for yes, 'n' for no, 'list' to see available environments."
                ;;
            *)
                echo "Invalid response: '$response'. Please answer 'y' for yes, 'n' for no, or 'list' to see available environments."
                ;;
        esac
    done
}

# Initialize summary counters
TOTAL_ENVIRONMENTS=0
SUCCESSFUL_COPIES=0
SKIPPED_ENVIRONMENTS=0
FAILED_COPIES=0

# Safety mode announcements
if [ "$DRY_RUN" = true ]; then
    echo "🛡️  ======================= SAFETY MODE: DRY RUN ======================="
    echo "🔍  This is a DRY RUN - NO CHANGES will be made to destination"
    echo "🔍  Script will show what WOULD be done without making changes"
    echo "🛡️  =================================================================="
    echo ""
fi

log_message "Starting cross-environment settings restoration"
log_message "Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN (SAFE)" || echo "LIVE (MAKING CHANGES)")$([ "$INTERACTIVE_MODE" = true ] && echo " - INTERACTIVE" || echo "")"
log_message "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER)"
log_message "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER)"
log_message "📁 Logging to: $LOG_FILE"
log_message "📊 Summary to: $SUMMARY_FILE"
log_message "🗺️  Mappings to: $MAPPING_FILE"

log_summary "Cross-Environment Settings Restoration Summary"
log_summary "Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN" || echo "LIVE")$([ "$INTERACTIVE_MODE" = true ] && echo " - INTERACTIVE" || echo "")"
log_summary "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER)"
log_summary "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER)"
log_summary "----------------------------------------"

# Validate tokens
if [ -z "$SOURCE_TOKEN" ] || [ -z "$DEST_TOKEN" ]; then
    log_message "Error: Both source and destination tokens are required"
    exit 1
fi

# Function to check authentication for both environments
check_auth() {
    log_message "Checking authentication for source environment..."
    local source_response=$(curl -s -w "%{http_code}" -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/clusters")
    local source_http_code=${source_response: -3}
    
    if [ "$source_http_code" != "200" ]; then
        log_message "ERROR: Source environment authentication failed. HTTP code: $source_http_code"
        return 1
    fi
    log_message "Source environment authentication successful"
    
    log_message "Checking authentication for destination environment..."
    local dest_response=$(curl -s -w "%{http_code}" -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/environments/api/clusters")
    local dest_http_code=${dest_response: -3}
    
    if [ "$dest_http_code" != "200" ]; then
        log_message "ERROR: Destination environment authentication failed. HTTP code: $dest_http_code"
        return 1
    fi
    log_message "Destination environment authentication successful"
    
    return 0
}

# Check authentication for both environments
if ! check_auth; then
    log_message "Authentication failed. Exiting."
    exit 1
fi

# Get source clusters with error handling
log_message "Fetching source clusters..."
SOURCE_CLUSTERS_RESPONSE=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/clusters" "${SOURCE_TOKEN}" "" "source clusters")
if [ $? -ne 0 ]; then
    log_message "Failed to get source clusters. Exiting."
    exit 1
fi

# Get destination clusters with error handling
log_message "Fetching destination clusters..."
DEST_CLUSTERS_RESPONSE=$(make_api_call "GET" "${DEST_API_ENDPOINT}/environments/api/clusters" "${DEST_TOKEN}" "" "destination clusters")
if [ $? -ne 0 ]; then
    log_message "Failed to get destination clusters. Exiting."
    exit 1
fi

# Get cluster IDs using the correct JSON path
SOURCE_CLUSTER_ID=$(echo "$SOURCE_CLUSTERS_RESPONSE" | jq -r --arg name "$SOURCE_CLUSTER" '.[] | select(.name == $name) | .id')
DEST_CLUSTER_ID=$(echo "$DEST_CLUSTERS_RESPONSE" | jq -r --arg name "$DEST_CLUSTER" '.[] | select(.name == $name) | .id')

if [ -z "$SOURCE_CLUSTER_ID" ] || [ -z "$DEST_CLUSTER_ID" ]; then
    log_message "Error: Could not find cluster IDs"
    log_message "Source cluster ($SOURCE_CLUSTER): $SOURCE_CLUSTER_ID"
    log_message "Destination cluster ($DEST_CLUSTER): $DEST_CLUSTER_ID"
    log_message "Available source clusters:"
    echo "$SOURCE_CLUSTERS_RESPONSE" | jq -r '.[].name'
    log_message "Available destination clusters:"
    echo "$DEST_CLUSTERS_RESPONSE" | jq -r '.[].name'
    exit 1
fi

log_message "Source cluster ID: $SOURCE_CLUSTER_ID"
log_message "Destination cluster ID: $DEST_CLUSTER_ID"

# Get source environments with error handling
log_message "Fetching source environments..."
SOURCE_ENVIRONMENTS_RESPONSE=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/environments" "${SOURCE_TOKEN}" "" "source environments")
if [ $? -ne 0 ]; then
    log_message "Failed to get source environments. Exiting."
    exit 1
fi

# Get destination environments with error handling
log_message "Fetching destination environments..."
DEST_ENVIRONMENTS_RESPONSE=$(make_api_call "GET" "${DEST_API_ENDPOINT}/environments/api/environments" "${DEST_TOKEN}" "" "destination environments")
if [ $? -ne 0 ]; then
    log_message "Failed to get destination environments. Exiting."
    exit 1
fi

# Get source environments using the correct JSON path
SOURCE_ENVIRONMENTS=$(echo "$SOURCE_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$SOURCE_CLUSTER_ID" '.[] | select(.cluster[].id == $cluster)')

if [ -z "$SOURCE_ENVIRONMENTS" ]; then
    log_message "No environments found in source cluster $SOURCE_CLUSTER"
    log_message "Source cluster ID: $SOURCE_CLUSTER_ID"
    log_message "Available source environments:"
    echo "$SOURCE_ENVIRONMENTS_RESPONSE" | jq -r '.[].name'
    exit 1
fi

# Function to get team rolebindings from source
get_source_team_rolebindings() {
    local env_id=$1
    local response
    response=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
        "$SOURCE_API_ENDPOINT/environments/api/environments/$env_id/teamrolebindings?fields=id,name,team,role")
    
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to get team rolebindings from source environment $env_id"
        return 1
    fi
    
    echo "$response"
}

# Function to create team rolebinding in destination
create_dest_team_rolebinding() {
    local env_id=$1
    local team_id=$2
    local role_id=$3
    local team_name=$4
    local permission=$5
    
    if [ "$DRY_RUN" = true ]; then
        log_message "🔍 [DRY-RUN] WOULD create team rolebinding for team '$team_name' with permission '$permission'"
        return 0
    fi
    
    log_message "Creating team rolebinding in destination for team $team_name with permission $permission"
    
    # Create payload for team rolebinding
    local payload="{
        \"modelIndex\": \"TeamRoleBinding\",
        \"parent\": {
            \"id\": \"$env_id\",
            \"service\": \"Environment\",
            \"modelIndex\": \"Environment\",
            \"childRelation\": \"teamrolebindings\"
        },
        \"team\": \"$team_id\",
        \"role\": \"$role_id\",
        \"permission\": \"$permission\"
    }"
    
    local response=$(curl -s -X POST -H "Authorization: NIRMATA-API $DEST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$DEST_API_ENDPOINT/environments/api/environments/$env_id/teamrolebindings")
    
    if [[ "$response" == *"error"* ]] || [[ "$response" == *"Error"* ]]; then
        log_message "ERROR: Failed to create team rolebinding for $team_name: $response"
        return 1
    fi
    
    log_message "Successfully created team rolebinding for team $team_name"
    return 0
}

# Function to find corresponding destination environment
find_dest_environment() {
    local source_env_name=$1
    
    log_message "Looking for destination environment matching source: $source_env_name" >&2
    
    # Validate input
    if [ -z "$source_env_name" ]; then
        log_message "ERROR: Empty source environment name provided" >&2
        return 1
    fi
    
    # Strategy 1: Exact match
    local dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$source_env_name" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
    
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found exact match: $source_env_name" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Strategy 2: Extract namespace from various patterns and try multiple matching approaches
    local namespace=""
    local source_cluster_lower=$(echo "$SOURCE_CLUSTER" | tr '[:upper:]' '[:lower:]')
    local dest_cluster_lower=$(echo "$DEST_CLUSTER" | tr '[:upper:]' '[:lower:]')
    
    # Pattern 1: clustername-namespace (remove cluster prefix)
    if [[ "$source_env_name" == "$SOURCE_CLUSTER-"* ]]; then
        namespace=$(echo "$source_env_name" | sed "s/^$SOURCE_CLUSTER-//")
        log_message "Detected cluster prefix pattern. Extracted namespace: $namespace" >&2
    # Pattern 2: namespace-clustername (remove cluster suffix)  
    elif [[ "$source_env_name" == *"-$SOURCE_CLUSTER" ]]; then
        namespace=$(echo "$source_env_name" | sed "s/-$SOURCE_CLUSTER$//")
        log_message "Detected cluster suffix pattern. Extracted namespace: $namespace" >&2
    # Pattern 3: Try case-insensitive cluster matching
    elif [[ "$(echo "$source_env_name" | tr '[:upper:]' '[:lower:]')" == "$source_cluster_lower-"* ]]; then
        namespace=$(echo "$(echo "$source_env_name" | tr '[:upper:]' '[:lower:]')" | sed "s/^$source_cluster_lower-//")
        log_message "Detected case-insensitive cluster prefix. Extracted namespace: $namespace" >&2
    elif [[ "$(echo "$source_env_name" | tr '[:upper:]' '[:lower:]')" == *"-$source_cluster_lower" ]]; then
        namespace=$(echo "$(echo "$source_env_name" | tr '[:upper:]' '[:lower:]')" | sed "s/-$source_cluster_lower$//")
        log_message "Detected case-insensitive cluster suffix. Extracted namespace: $namespace" >&2
    # Pattern 4: Remove any numeric suffixes and try again
    else
        namespace=$(echo "$source_env_name" | sed 's/-[0-9]*$//')
        log_message "No cluster pattern detected. Using name as namespace (with numeric suffix removed): $namespace" >&2
    fi
    
    if [ -z "$namespace" ]; then
        namespace="$source_env_name"
        log_message "Using full source name as namespace: $namespace" >&2
    fi
    
    # Strategy 3: Try to find destination environment using extracted namespace
    # Try multiple destination patterns
    
    # Pattern A: exact namespace match
    dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$namespace" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found namespace-only match: $namespace" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Pattern B: destcluster-namespace
    local dest_pattern="$DEST_CLUSTER-$namespace"
    dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$dest_pattern" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found cluster-prefix match: $dest_pattern" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Pattern C: namespace-destcluster
    dest_pattern="$namespace-$DEST_CLUSTER"
    dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$dest_pattern" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found cluster-suffix match: $dest_pattern" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Pattern D: Case-insensitive versions
    dest_pattern="$dest_cluster_lower-$namespace"
    dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$dest_pattern" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found case-insensitive cluster-prefix match: $dest_pattern" >&2
        echo "$dest_env"
        return 0
    fi
    
    dest_pattern="$namespace-$dest_cluster_lower"
    dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$dest_pattern" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found case-insensitive cluster-suffix match: $dest_pattern" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Pattern E: Special migration pattern - replace source cluster with destination cluster
    # Convert "name-conformance-132" to "name-old-app-migration"
    dest_pattern=$(echo "$source_env_name" | sed "s/-$SOURCE_CLUSTER$/-$DEST_CLUSTER/")
    if [ "$dest_pattern" != "$source_env_name" ]; then
        dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$dest_pattern" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
        if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
            log_message "Found migration pattern match: $dest_pattern" >&2
            echo "$dest_env"
            return 0
        fi
    fi
    
    # Strategy 4: Fuzzy matching - contains the namespace
    dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg pattern "$namespace" '.[] | select(.cluster[0].id == $cluster and (.name | contains($pattern)))')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        local matched_name=$(echo "$dest_env" | jq -r '.name')
        log_message "Found fuzzy match containing '$namespace': $matched_name" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Strategy 5: Last resort - list all available destination environments for debugging
    log_message "No match found for source environment: $source_env_name" >&2
    log_message "Extracted namespace: $namespace" >&2
    log_message "Available destination environments in cluster $DEST_CLUSTER:" >&2
    
    # Fixed: Better error handling for jq parsing
    local env_list
    env_list=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" '.[] | select(.cluster[0].id == $cluster) | .name' 2>/dev/null | head -10)
    
    if [ $? -eq 0 ] && [ ! -z "$env_list" ]; then
        echo "$env_list" | while read -r env_name; do
            log_message "  - $env_name" >&2
        done
    else
        log_message "ERROR: Failed to parse destination environments list" >&2
    fi
    
    return 1
}

# Function to map team ID from source to destination by name
map_team_id_by_name() {
    local source_team_id=$1
    local source_team_name=$2
    
    # If team name is provided, use it to find destination team ID
    if [ ! -z "$source_team_name" ] && [ "$source_team_name" != "null" ]; then
        local dest_team_id=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
            "$DEST_API_ENDPOINT/users/api/teams" | \
            jq -r --arg name "$source_team_name" '.[] | select(.name == $name) | .id')
        
        if [ ! -z "$dest_team_id" ] && [ "$dest_team_id" != "null" ]; then
            echo "$dest_team_id"
            return 0
        fi
    fi
    
    # Fallback: return empty if no mapping found
    echo ""
    return 1
}

# Function to copy team rolebindings from source to destination
copy_all_environment_settings() {
    local source_env_id=$1
    local dest_env_id=$2
    local source_env_name=$3
    local dest_env_name=$4
    
    log_message "Copying ALL environment settings from source $source_env_name to destination $dest_env_name"
    
    # Get source environment details with error handling
    SOURCE_ENV_DETAILS=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/environments/$source_env_id" "${SOURCE_TOKEN}" "" "source environment details")
    if [ $? -ne 0 ]; then
        log_message "Failed to get source environment details for $source_env_name"
        return 1
    fi
    
    # 1. Copy resource type
    RESOURCE_TYPE=$(safe_json_extract "$SOURCE_ENV_DETAILS" '.resourceType' "")
    if [ ! -z "$RESOURCE_TYPE" ]; then
        log_message "Copying resource type: $RESOURCE_TYPE"
        if [ "$DRY_RUN" = false ]; then
            RESOURCE_TYPE_RESPONSE=$(make_api_call "PUT" "${DEST_API_ENDPOINT}/environments/api/environments/$dest_env_id" "${DEST_TOKEN}" "{\"resourceType\":\"$RESOURCE_TYPE\"}" "resource type update")
            if [ $? -eq 0 ]; then
                log_message "Resource type copied successfully"
            else
                log_message "WARNING: Failed to copy resource type"
            fi
        else
            log_message "🔍 [DRY-RUN] WOULD copy resource type: $RESOURCE_TYPE"
        fi
    else
        log_message "No resource type found in source environment"
    fi
    
    # 2. Copy Resource Quotas
    log_message "Copying resource quotas..."
    SOURCE_QUOTAS=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/environments/${source_env_id}/resourceQuota" "${SOURCE_TOKEN}" "" "resource quotas")
    
    if [ $? -eq 0 ] && [ ! -z "$SOURCE_QUOTAS" ] && [ "$SOURCE_QUOTAS" != "[]" ]; then
        echo "$SOURCE_QUOTAS" | jq -c '.[]' 2>/dev/null | while read -r quota; do
            QUOTA_NAME=$(safe_json_extract "$quota" '.name' "")
            QUOTA_SPEC=$(echo "$quota" | jq -c '.spec' 2>/dev/null)
            
            if [ ! -z "$QUOTA_NAME" ] && [ ! -z "$QUOTA_SPEC" ] && [ "$QUOTA_SPEC" != "null" ]; then
                log_message "Processing quota: $QUOTA_NAME"
                log_message "Quota spec: $QUOTA_SPEC"
                
                # Build quota payload
                QUOTA_PAYLOAD="{\"name\":\"${QUOTA_NAME}\",\"spec\":${QUOTA_SPEC}}"
                
                if [ "$DRY_RUN" = false ]; then
                    QUOTA_RESPONSE=$(make_api_call "POST" "${DEST_API_ENDPOINT}/environments/api/environments/${dest_env_id}/resourceQuota" "${DEST_TOKEN}" "${QUOTA_PAYLOAD}" "resource quota creation")
                    
                    if [ $? -eq 0 ]; then
                        log_message "Successfully created quota $QUOTA_NAME"
                    else
                        log_message "WARNING: Failed to create quota $QUOTA_NAME"
                        log_message "Quota payload was: $QUOTA_PAYLOAD"
                        log_message "This may be due to quota conflicts, permissions, or API limitations"
                    fi
                else
                    log_message "🔍 [DRY-RUN] WOULD create quota: $QUOTA_NAME with spec: $QUOTA_SPEC"
                fi
            else
                log_message "WARNING: Skipping invalid quota entry - Name: '$QUOTA_NAME', Spec: '$QUOTA_SPEC'"
            fi
        done
    else
        log_message "No resource quotas found in source environment"
    fi
    
    # 3. Copy Limit Ranges with Complete Configuration
    log_message "Copying limit ranges..."
    SOURCE_LIMITS=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/environments/${source_env_id}/limitRange" "${SOURCE_TOKEN}" "" "limit ranges")
    
    if [ $? -eq 0 ] && [ ! -z "$SOURCE_LIMITS" ] && [ "$SOURCE_LIMITS" != "[]" ]; then
        echo "$SOURCE_LIMITS" | jq -c '.[]' 2>/dev/null | while read -r limit; do
            LIMIT_NAME=$(safe_json_extract "$limit" '.name' "")
            LIMIT_ID=$(safe_json_extract "$limit" '.id' "")
            
            if [ ! -z "$LIMIT_NAME" ] && [ ! -z "$LIMIT_ID" ]; then
                log_message "Processing limit range: $LIMIT_NAME (ID: $LIMIT_ID)"
                
                # Get detailed limit range configuration from source
                SOURCE_LIMIT_DETAILS=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/limitRanges/$LIMIT_ID" "${SOURCE_TOKEN}" "" "limit range details")
                
                if [ $? -eq 0 ]; then
                    log_message "Source limit details: $SOURCE_LIMIT_DETAILS"
                    
                    # Get the limit range configuration using the nested API structure
                    LIMITS_CONFIG=""
                    
                    # Approach 1: Get from nested spec structure (most reliable)
                    LIMIT_SPEC_ID=$(echo "$SOURCE_LIMIT_DETAILS" | jq -r '.spec[0].id' 2>/dev/null)
                    
                    if [ ! -z "$LIMIT_SPEC_ID" ] && [ "$LIMIT_SPEC_ID" != "null" ]; then
                        log_message "Getting limit range spec from ID: $LIMIT_SPEC_ID"
                        SOURCE_LIMIT_SPEC=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/limitRangeSpecs/$LIMIT_SPEC_ID" "${SOURCE_TOKEN}" "" "limit range spec")
                        
                        if [ $? -eq 0 ]; then
                            # Get limit range items from the spec
                            LIMIT_ITEMS=$(echo "$SOURCE_LIMIT_SPEC" | jq -r '.limits[].id' 2>/dev/null)
                            
                            if [ ! -z "$LIMIT_ITEMS" ]; then
                                log_message "Found limit range items: $LIMIT_ITEMS"
                                
                                # Build limits array from individual limit range items
                                LIMITS_ARRAY="["
                                local first_item=true
                                
                                for item_id in $LIMIT_ITEMS; do
                                    if [ ! -z "$item_id" ] && [ "$item_id" != "null" ]; then
                                        log_message "Getting limit range item details for: $item_id"
                                        ITEM_DETAILS=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/limitRangeItems/$item_id" "${SOURCE_TOKEN}" "" "limit range item")
                                        
                                        if [ $? -eq 0 ]; then
                                            # Extract limit details
                                            ITEM_TYPE=$(safe_json_extract "$ITEM_DETAILS" '.type' "Container")
                                            DEFAULT_LIMIT=$(echo "$ITEM_DETAILS" | jq -c '.defaultLimit' 2>/dev/null)
                                            DEFAULT_REQUEST=$(echo "$ITEM_DETAILS" | jq -c '.defaultRequest' 2>/dev/null)
                                            MAX_LIMIT=$(echo "$ITEM_DETAILS" | jq -c '.max' 2>/dev/null)
                                            MIN_LIMIT=$(echo "$ITEM_DETAILS" | jq -c '.min' 2>/dev/null)
                                            MAX_RATIO=$(echo "$ITEM_DETAILS" | jq -c '.maxLimitRequestRatio' 2>/dev/null)
                                            
                                            # Check if defaultLimit is empty but additionalProperties.default exists
                                            if [ -z "$DEFAULT_LIMIT" ] || [ "$DEFAULT_LIMIT" = "{}" ] || [ "$DEFAULT_LIMIT" = "null" ]; then
                                                ADDITIONAL_DEFAULT=$(echo "$ITEM_DETAILS" | jq -c '.additionalProperties.default' 2>/dev/null)
                                                if [ ! -z "$ADDITIONAL_DEFAULT" ] && [ "$ADDITIONAL_DEFAULT" != "{}" ] && [ "$ADDITIONAL_DEFAULT" != "null" ]; then
                                                    DEFAULT_LIMIT="$ADDITIONAL_DEFAULT"
                                                    log_message "Found default limits in additionalProperties: $DEFAULT_LIMIT"
                                                fi
                                            fi
                                            
                                            # Build limit item JSON
                                            if [ "$first_item" = false ]; then
                                                LIMITS_ARRAY="$LIMITS_ARRAY,"
                                            fi
                                            first_item=false
                                            
                                            LIMITS_ARRAY="$LIMITS_ARRAY{\"type\":\"$ITEM_TYPE\""
                                            
                                            # Add non-empty fields (note: API stores as defaultLimit but expects 'default' in payload)
                                            if [ ! -z "$DEFAULT_LIMIT" ] && [ "$DEFAULT_LIMIT" != "{}" ] && [ "$DEFAULT_LIMIT" != "null" ]; then
                                                LIMITS_ARRAY="$LIMITS_ARRAY,\"default\":$DEFAULT_LIMIT"
                                            fi
                                            if [ ! -z "$DEFAULT_REQUEST" ] && [ "$DEFAULT_REQUEST" != "{}" ] && [ "$DEFAULT_REQUEST" != "null" ]; then
                                                LIMITS_ARRAY="$LIMITS_ARRAY,\"defaultRequest\":$DEFAULT_REQUEST"
                                            fi
                                            if [ ! -z "$MAX_LIMIT" ] && [ "$MAX_LIMIT" != "{}" ] && [ "$MAX_LIMIT" != "null" ]; then
                                                LIMITS_ARRAY="$LIMITS_ARRAY,\"max\":$MAX_LIMIT"
                                            fi
                                            if [ ! -z "$MIN_LIMIT" ] && [ "$MIN_LIMIT" != "{}" ] && [ "$MIN_LIMIT" != "null" ]; then
                                                LIMITS_ARRAY="$LIMITS_ARRAY,\"min\":$MIN_LIMIT"
                                            fi
                                            if [ ! -z "$MAX_RATIO" ] && [ "$MAX_RATIO" != "{}" ] && [ "$MAX_RATIO" != "null" ]; then
                                                LIMITS_ARRAY="$LIMITS_ARRAY,\"maxLimitRequestRatio\":$MAX_RATIO"
                                            fi
                                            
                                            LIMITS_ARRAY="$LIMITS_ARRAY}"
                                            
                                            log_message "Added limit item: type=$ITEM_TYPE, default=$DEFAULT_LIMIT, defaultRequest=$DEFAULT_REQUEST"
                                        fi
                                    fi
                                done
                                
                                LIMITS_ARRAY="$LIMITS_ARRAY]"
                                LIMITS_CONFIG="$LIMITS_ARRAY"
                                log_message "Built complete limits configuration: $LIMITS_CONFIG"
                            else
                                log_message "No limit range items found in spec"
                            fi
                        fi
                    fi
                    
                    # Approach 2: Try to get the raw Kubernetes manifest as fallback
                    if [ -z "$LIMITS_CONFIG" ] || [ "$LIMITS_CONFIG" = "null" ] || [ "$LIMITS_CONFIG" = "[]" ]; then
                        log_message "Trying to get Kubernetes manifest for limit range..."
                        K8S_MANIFEST=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/limitRanges/$LIMIT_ID/manifest" "${SOURCE_TOKEN}" "" "limit range manifest")
                        
                        if [ $? -eq 0 ]; then
                            LIMITS_CONFIG=$(echo "$K8S_MANIFEST" | jq -c '.spec.limits' 2>/dev/null)
                            log_message "Retrieved limits from Kubernetes manifest: $LIMITS_CONFIG"
                        fi
                    fi
                    
                    if [ ! -z "$LIMITS_CONFIG" ] && [ "$LIMITS_CONFIG" != "null" ] && [ "$LIMITS_CONFIG" != "[]" ]; then
                        log_message "Found valid limits configuration: $LIMITS_CONFIG"
                        
                        # Build complete limit range payload using Kubernetes-native format
                        LIMIT_PAYLOAD=$(cat <<EOF
{
    "name": "${LIMIT_NAME}",
    "spec": {
        "limits": ${LIMITS_CONFIG}
    }
}
EOF
)
                        
                        if [ "$DRY_RUN" = false ]; then
                            # First, delete existing limit range if it exists
                            log_message "Removing existing limit range $LIMIT_NAME if present..."
                            EXISTING_LIMITS=$(make_api_call "GET" "${DEST_API_ENDPOINT}/environments/api/environments/${dest_env_id}/limitRange" "${DEST_TOKEN}" "" "existing limit ranges")
                            
                            if [ $? -eq 0 ]; then
                                EXISTING_LIMIT_ID=$(echo "$EXISTING_LIMITS" | jq -r --arg name "$LIMIT_NAME" '.[] | select(.name == $name) | .id' 2>/dev/null)
                                
                                if [ ! -z "$EXISTING_LIMIT_ID" ] && [ "$EXISTING_LIMIT_ID" != "null" ]; then
                                    log_message "Deleting existing limit range: $LIMIT_NAME (ID: $EXISTING_LIMIT_ID)"
                                    DELETE_RESPONSE=$(curl -s -X DELETE -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                                        "${DEST_API_ENDPOINT}/environments/api/limitRanges/$EXISTING_LIMIT_ID")
                                    log_message "Delete response: $DELETE_RESPONSE"
                                    
                                    # Wait a moment for deletion to complete
                                    sleep 2
                                fi
                            fi
                            
                            # Create new limit range with complete configuration
                            log_message "Creating limit range with payload: $LIMIT_PAYLOAD"
                            LIMIT_RESPONSE=$(make_api_call "POST" "${DEST_API_ENDPOINT}/environments/api/environments/${dest_env_id}/limitRange" "${DEST_TOKEN}" "${LIMIT_PAYLOAD}" "limit range creation")
                            
                            if [ $? -eq 0 ]; then
                                log_message "Successfully created limit range $LIMIT_NAME with configuration"
                                log_message "Creation response: $LIMIT_RESPONSE"
                                
                                # Verify the created limit range has the correct configuration
                                NEW_LIMIT_ID=$(echo "$LIMIT_RESPONSE" | jq -r '.id' 2>/dev/null)
                                if [ ! -z "$NEW_LIMIT_ID" ] && [ "$NEW_LIMIT_ID" != "null" ]; then
                                    sleep 3  # Wait for resource to be fully created
                                    VERIFICATION=$(make_api_call "GET" "${DEST_API_ENDPOINT}/environments/api/limitRanges/$NEW_LIMIT_ID" "${DEST_TOKEN}" "" "limit range verification")
                                    if [ $? -eq 0 ]; then
                                        log_message "Verification - Created limit range details: $VERIFICATION"
                                    fi
                                fi
                            else
                                log_message "WARNING: Failed to create limit range $LIMIT_NAME"
                                log_message "Trying alternative API approach..."
                                
                                # Alternative approach: Try using the Kubernetes manifest API
                                K8S_LIMIT_PAYLOAD=$(cat <<EOF
{
    "apiVersion": "v1",
    "kind": "LimitRange",
    "metadata": {
        "name": "${LIMIT_NAME}"
    },
    "spec": {
        "limits": ${LIMITS_CONFIG}
    }
}
EOF
)
                                
                                ALT_RESPONSE=$(make_api_call "POST" "${DEST_API_ENDPOINT}/environments/api/environments/${dest_env_id}/resources" "${DEST_TOKEN}" "${K8S_LIMIT_PAYLOAD}" "limit range K8s creation")
                                
                                if [ $? -eq 0 ]; then
                                    log_message "Successfully created limit range $LIMIT_NAME using Kubernetes API"
                                else
                                    log_message "ERROR: Both limit range creation methods failed for $LIMIT_NAME"
                                fi
                            fi
                        else
                            log_message "🔍 [DRY-RUN] WOULD create limit range: $LIMIT_NAME with limits: $LIMITS_CONFIG"
                        fi
                    else
                        log_message "WARNING: No valid limits configuration found for limit range $LIMIT_NAME"
                        log_message "Raw limit details: $SOURCE_LIMIT_DETAILS"
                    fi
                else
                    log_message "WARNING: Failed to get detailed limit range for $LIMIT_NAME"
                fi
            else
                log_message "WARNING: Skipping invalid limit range entry"
            fi
        done
    else
        log_message "No limit ranges found in source environment"
    fi
    
    # 4. Copy Access Controls (ACLs) - Clean and Replace
    SOURCE_ACL_ID=$(safe_json_extract "$SOURCE_ENV_DETAILS" '.accessControlList[0].id' "")
    if [ ! -z "$SOURCE_ACL_ID" ]; then
        log_message "Copying access controls from ACL: $SOURCE_ACL_ID"
        
        # Get source ACL details
        SOURCE_ACL_DETAILS=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/accessControlLists/$SOURCE_ACL_ID" "${SOURCE_TOKEN}" "" "source ACL details")
        if [ $? -ne 0 ]; then
            log_message "WARNING: Failed to get source ACL details"
            return 1
        fi
        
        # Get destination ACL ID
        DEST_ENV_DETAILS=$(make_api_call "GET" "${DEST_API_ENDPOINT}/environments/api/environments/$dest_env_id" "${DEST_TOKEN}" "" "destination environment details")
        if [ $? -ne 0 ]; then
            log_message "WARNING: Failed to get destination environment details"
            return 1
        fi
        
        DEST_ACL_ID=$(safe_json_extract "$DEST_ENV_DETAILS" '.accessControlList[0].id' "")
        
        if [ ! -z "$DEST_ACL_ID" ]; then
            log_message "Destination ACL ID: $DEST_ACL_ID"
            
            # STEP 1: Clean existing team/user ACLs (keep only role-based ACLs)
            log_message "Cleaning existing team/user permissions from destination..."
            
            if [ "$DRY_RUN" = false ]; then
                # Get existing destination ACLs
                DEST_ACL_DETAILS=$(make_api_call "GET" "${DEST_API_ENDPOINT}/environments/api/accessControlLists/$DEST_ACL_ID" "${DEST_TOKEN}" "" "destination ACL details")
                if [ $? -eq 0 ]; then
                    # Delete existing team and user ACLs (keep roles)
                    echo "$DEST_ACL_DETAILS" | jq -r '.accessControls[].id' 2>/dev/null | while read -r existing_acl_id; do
                        if [ ! -z "$existing_acl_id" ] && [ "$existing_acl_id" != "null" ]; then
                            # Get ACL details to check entity type
                            EXISTING_ACL_DETAILS=$(make_api_call "GET" "${DEST_API_ENDPOINT}/environments/api/accessControls/$existing_acl_id" "${DEST_TOKEN}" "" "existing ACL details")
                            if [ $? -eq 0 ]; then
                                EXISTING_ENTITY_TYPE=$(safe_json_extract "$EXISTING_ACL_DETAILS" '.entityType' "")
                                EXISTING_ENTITY_NAME=$(safe_json_extract "$EXISTING_ACL_DETAILS" '.entityName' "")
                                
                                if [ "$EXISTING_ENTITY_TYPE" = "team" ] || [ "$EXISTING_ENTITY_TYPE" = "user" ]; then
                                    log_message "Removing existing $EXISTING_ENTITY_TYPE ACL: $EXISTING_ENTITY_NAME"
                                    DELETE_RESPONSE=$(curl -s -X DELETE -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                                        "${DEST_API_ENDPOINT}/environments/api/accessControls/$existing_acl_id")
                                fi
                            fi
                        fi
                    done
                fi
            else
                log_message "🔍 [DRY-RUN] WOULD clean existing team/user permissions"
            fi
            
            # STEP 2: Add source ACLs with proper team mapping
        # Get access control IDs
            ACCESS_CONTROL_IDS=$(echo "$SOURCE_ACL_DETAILS" | jq -r '.accessControls[].id' 2>/dev/null)
        
        # Process each access control
        for control_id in $ACCESS_CONTROL_IDS; do
                if [ ! -z "$control_id" ] && [ "$control_id" != "null" ]; then
            # Get access control details from source
                    CONTROL_DETAILS=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/accessControls/$control_id" "${SOURCE_TOKEN}" "" "access control details")
                    if [ $? -ne 0 ]; then
                        log_message "WARNING: Failed to get access control details for $control_id"
                        continue
                    fi
            
                    ENTITY_ID=$(safe_json_extract "$CONTROL_DETAILS" '.entityId' "")
                    ENTITY_TYPE=$(safe_json_extract "$CONTROL_DETAILS" '.entityType' "")
                    PERMISSION=$(safe_json_extract "$CONTROL_DETAILS" '.permission' "")
                    ENTITY_NAME=$(safe_json_extract "$CONTROL_DETAILS" '.entityName' "")
            
                    if [ "$ENTITY_TYPE" = "team" ] && [ ! -z "$ENTITY_ID" ] && [ ! -z "$PERMISSION" ] && [ ! -z "$ENTITY_NAME" ]; then
                        log_message "Mapping team $ENTITY_NAME from source ID $ENTITY_ID to destination cluster"
                        
                        # Map team ID from source to destination by name
                        DEST_TEAM_ID=$(map_team_id_by_name "$ENTITY_ID" "$ENTITY_NAME")
                        
                        if [ ! -z "$DEST_TEAM_ID" ]; then
                            log_message "Successfully mapped team $ENTITY_NAME: $ENTITY_ID → $DEST_TEAM_ID"
                            
                            if [ "$DRY_RUN" = false ]; then
                                # Create ACL entry using destination team ID
                                ACL_PAYLOAD="{\"entityId\":\"$DEST_TEAM_ID\",\"entityType\":\"team\",\"permission\":\"$PERMISSION\",\"entityName\":\"$ENTITY_NAME\"}"
                                ACL_RESPONSE=$(make_api_call "POST" "${DEST_API_ENDPOINT}/environments/api/accessControlLists/$DEST_ACL_ID/accessControls" "${DEST_TOKEN}" "$ACL_PAYLOAD" "team ACL creation")
                                
                                if [ $? -eq 0 ]; then
                                    log_message "Successfully created ACL for team $ENTITY_NAME with destination ID $DEST_TEAM_ID"
                                else
                                    log_message "WARNING: Failed to create ACL for team $ENTITY_NAME"
                                fi
                            else
                                log_message "🔍 [DRY-RUN] WOULD create ACL for team $ENTITY_NAME with permission $PERMISSION (mapped ID: $DEST_TEAM_ID)"
                            fi
                        else
                            log_message "WARNING: Team $ENTITY_NAME not found in destination cluster - skipping ACL creation"
                        fi
                    elif [ "$ENTITY_TYPE" = "user" ] && [ ! -z "$ENTITY_ID" ] && [ ! -z "$PERMISSION" ] && [ ! -z "$ENTITY_NAME" ]; then
                        log_message "Creating ACL for user $ENTITY_NAME ($ENTITY_ID) with permission $PERMISSION"
                        
                        if [ "$DRY_RUN" = false ]; then
                            ACL_PAYLOAD="{\"entityId\":\"$ENTITY_ID\",\"entityType\":\"user\",\"permission\":\"$PERMISSION\",\"entityName\":\"$ENTITY_NAME\"}"
                            ACL_RESPONSE=$(make_api_call "POST" "${DEST_API_ENDPOINT}/environments/api/accessControlLists/$DEST_ACL_ID/accessControls" "${DEST_TOKEN}" "$ACL_PAYLOAD" "user ACL creation")
                            
                            if [ $? -eq 0 ]; then
                                log_message "Successfully created ACL for user $ENTITY_NAME"
                            else
                                log_message "WARNING: Failed to create ACL for user $ENTITY_NAME"
                            fi
                        else
                            log_message "🔍 [DRY-RUN] WOULD create ACL for user $ENTITY_NAME with permission $PERMISSION"
                        fi
                    elif [ "$ENTITY_TYPE" = "role" ]; then
                        log_message "Skipping role ACL (system managed): $ENTITY_NAME"
                    elif [ ! -z "$ENTITY_TYPE" ]; then
                        log_message "Unknown entity type: $ENTITY_TYPE for $ENTITY_NAME"
                    else
                        log_message "WARNING: Skipping ACL entry with missing required fields"
                    fi
                fi
            done
        else
            log_message "Warning: Could not find destination ACL ID"
        fi
    else
        log_message "No access control list found in source environment"
    fi
    
    # 5. Copy Labels
    log_message "Copying labels..."
    LABELS=$(echo "$SOURCE_ENV_DETAILS" | jq -c '.labels' 2>/dev/null)
    if [ ! -z "$LABELS" ] && [ "$LABELS" != "null" ] && [ "$LABELS" != "{}" ]; then
        log_message "Source labels: $LABELS"
        if [ "$DRY_RUN" = false ]; then
            LABELS_RESPONSE=$(make_api_call "PUT" "${DEST_API_ENDPOINT}/environments/api/environments/$dest_env_id" "${DEST_TOKEN}" "{\"labels\":$LABELS}" "labels update")
            if [ $? -eq 0 ]; then
                log_message "Successfully updated labels"
            else
                log_message "WARNING: Failed to update labels"
            fi
        else
            log_message "🔍 [DRY-RUN] WOULD copy labels: $LABELS"
        fi
    else
        log_message "No labels found in source environment"
    fi
    
    # 6. Copy Owner Details
    log_message "Copying owner details..."
    OWNER=$(safe_json_extract "$SOURCE_ENV_DETAILS" '.createdBy' "")
    if [ ! -z "$OWNER" ]; then
        log_message "Setting owner to: $OWNER"
        if [ "$DRY_RUN" = false ]; then
            OWNER_RESPONSE=$(make_api_call "PUT" "${DEST_API_ENDPOINT}/environments/api/environments/$dest_env_id" "${DEST_TOKEN}" "{\"createdBy\":\"$OWNER\",\"modifiedBy\":\"$OWNER\"}" "owner update")
            if [ $? -eq 0 ]; then
                log_message "Successfully updated owner details"
            else
                log_message "WARNING: Failed to update owner details"
            fi
        else
            log_message "🔍 [DRY-RUN] WOULD set owner to: $OWNER"
        fi
    else
        log_message "No owner information found in source environment"
    fi
    
    # 7. Copy Update Policies
    log_message "Copying update policies..."
    UPDATE_POLICIES=$(echo "$SOURCE_ENV_DETAILS" | jq -c '.updatePolicy' 2>/dev/null)
    if [ ! -z "$UPDATE_POLICIES" ] && [ "$UPDATE_POLICIES" != "null" ] && [ "$UPDATE_POLICIES" != "[]" ]; then
        log_message "Found update policies in source environment: $UPDATE_POLICIES"
        if [ "$DRY_RUN" = false ]; then
            # Try to copy update policies - this may need adjustment based on API structure
            POLICY_RESPONSE=$(make_api_call "PUT" "${DEST_API_ENDPOINT}/environments/api/environments/$dest_env_id" "${DEST_TOKEN}" "{\"updatePolicy\":$UPDATE_POLICIES}" "update policy")
            if [ $? -eq 0 ]; then
                log_message "Successfully copied update policies"
            else
                log_message "WARNING: Failed to copy update policies - may require manual configuration"
            fi
        else
            log_message "🔍 [DRY-RUN] WOULD copy update policies: $UPDATE_POLICIES"
        fi
    else
        log_message "No update policies found in source environment"
    fi
    
    # 8. Copy Kubernetes Resources (RoleBindings, ConfigMaps, etc.)
    log_message "Copying Kubernetes resources from source environment..."
    
    # Get all resources from source environment
    SOURCE_RESOURCES=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/environments/${source_env_id}/resources" "${SOURCE_TOKEN}" "" "source environment resources")
    
    if [ $? -eq 0 ] && [ ! -z "$SOURCE_RESOURCES" ] && [ "$SOURCE_RESOURCES" != "[]" ]; then
        # Count resources first
        local total_resources=$(echo "$SOURCE_RESOURCES" | jq '. | length' 2>/dev/null)
        log_message "Found $total_resources Kubernetes resources in source environment"
        
        # Process resources and track counts
        local resource_count=0
        local copied_count=0
        local skipped_count=0
        
        # Create temporary file to track results
        local temp_results="/tmp/k8s_copy_results_$$"
        echo "0 0 0" > "$temp_results"
        
        echo "$SOURCE_RESOURCES" | jq -c '.[]' 2>/dev/null | while read -r resource; do
            resource_count=$((resource_count + 1))
            
            RESOURCE_KIND=$(safe_json_extract "$resource" '.kind' "")
            RESOURCE_NAME=$(safe_json_extract "$resource" '.metadata.name' "")
            RESOURCE_NAMESPACE=$(safe_json_extract "$resource" '.metadata.namespace' "")
            
            if [ ! -z "$RESOURCE_KIND" ] && [ ! -z "$RESOURCE_NAME" ]; then
                log_message "Processing resource: $RESOURCE_KIND/$RESOURCE_NAME"
                
                # Skip certain system resources that shouldn't be copied
                case "$RESOURCE_KIND" in
                    "ServiceAccount")
                        if [[ "$RESOURCE_NAME" == "default" ]]; then
                            log_message "Skipping default ServiceAccount"
                            skipped_count=$((skipped_count + 1))
                            echo "$resource_count $copied_count $skipped_count" > "$temp_results"
                            continue
                        fi
                        ;;
                    "Secret")
                        if [[ "$RESOURCE_NAME" == *"token"* ]] || [[ "$RESOURCE_NAME" == "default-token"* ]]; then
                            log_message "Skipping system token secret: $RESOURCE_NAME"
                            skipped_count=$((skipped_count + 1))
                            echo "$resource_count $copied_count $skipped_count" > "$temp_results"
                            continue
                        fi
                            ;;
                    esac
                    
                if [ "$DRY_RUN" = false ]; then
                    # Clean up resource for copying (remove status, resourceVersion, etc.)
                    CLEAN_RESOURCE=$(echo "$resource" | jq '
                        del(.metadata.resourceVersion, .metadata.uid, .metadata.selfLink, 
                            .metadata.creationTimestamp, .metadata.generation, 
                            .metadata.managedFields, .status)')
                    
                    # Try to create the resource in destination
                    RESOURCE_RESPONSE=$(make_api_call "POST" "${DEST_API_ENDPOINT}/environments/api/environments/${dest_env_id}/resources" "${DEST_TOKEN}" "$CLEAN_RESOURCE" "resource creation")
                    
                    if [ $? -eq 0 ]; then
                        log_message "Successfully copied resource: $RESOURCE_KIND/$RESOURCE_NAME"
                        copied_count=$((copied_count + 1))
                    else
                        log_message "WARNING: Failed to copy resource: $RESOURCE_KIND/$RESOURCE_NAME (may already exist)"
                        # Don't count as failure since it might already exist
                        skipped_count=$((skipped_count + 1))
                    fi
                else
                    log_message "🔍 [DRY-RUN] WOULD copy resource: $RESOURCE_KIND/$RESOURCE_NAME"
                    copied_count=$((copied_count + 1))
                fi
            else
                log_message "WARNING: Skipping resource with missing kind or name"
                log_message "Resource data: $(echo "$resource" | jq -c '.' 2>/dev/null || echo "Invalid JSON")"
                skipped_count=$((skipped_count + 1))
            fi
            
            # Update results file
            echo "$resource_count $copied_count $skipped_count" > "$temp_results"
        done
        
        # Read final counts
        if [ -f "$temp_results" ]; then
            read -r final_resource_count final_copied_count final_skipped_count < "$temp_results"
            log_message "Kubernetes resources summary: $final_resource_count total, $final_copied_count copied, $final_skipped_count skipped"
            rm -f "$temp_results"
        else
            log_message "Kubernetes resources processing completed (counts unavailable due to subshell limitation)"
        fi
    else
        log_message "No Kubernetes resources found in source environment"
        log_message "This could indicate:"
        log_message "  - Environment has no custom resources"
        log_message "  - API endpoint access issues"
        log_message "  - Authentication problems for resources API"
        
        # Try alternative resources API if available
        if [ "$DRY_RUN" = false ]; then
            log_message "Attempting alternative resources API..."
            ALT_RESOURCES=$(make_api_call "GET" "${SOURCE_API_ENDPOINT}/environments/api/environments/${source_env_id}/k8sresources" "${SOURCE_TOKEN}" "" "alternative resources API")
            if [ $? -eq 0 ] && [ ! -z "$ALT_RESOURCES" ] && [ "$ALT_RESOURCES" != "[]" ]; then
                log_message "Found resources via alternative API: $(echo "$ALT_RESOURCES" | jq '. | length' 2>/dev/null) items"
            else
                log_message "Alternative resources API also returned no results"
            fi
        fi
    fi
    
    log_message "Completed copying all environment settings from $source_env_name to $dest_env_name"
    return 0
}

# Function to check if environment is a system namespace that should be skipped
is_system_namespace() {
    local env_name=$1
    
    # List of system namespaces to skip
    local system_namespaces=(
        "nirmata"
        "kyverno"
        "ingress-haproxy"
        "kube-node-lease"
        "kube-system"
        "kube-public"
        "default"
        "nirmata-system"
        "kyverno-system"
        "ingress-nginx"
        "cert-manager"
        "monitoring"
        "logging"
    )
    
    # Check if environment name matches any system namespace patterns
    for sys_ns in "${system_namespaces[@]}"; do
        # Exact match
        if [ "$env_name" = "$sys_ns" ]; then
            return 0
        fi
        
        # Pattern match with cluster suffix (e.g., kube-system-conformance-132)
        if [[ "$env_name" == "$sys_ns-"* ]]; then
            return 0
        fi
        
        # Pattern match with cluster prefix (e.g., conformance-132-kube-system)
        if [[ "$env_name" == *"-$sys_ns" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Function to copy environment settings
copy_environment_settings() {
    local source_env_name=$1
    local source_env_data=$2
    
    TOTAL_ENVIRONMENTS=$((TOTAL_ENVIRONMENTS + 1))
    
    # Check if this is a system namespace that should be skipped
    if is_system_namespace "$source_env_name"; then
        log_message "Skipping system namespace: $source_env_name"
        SKIPPED_ENVIRONMENTS=$((SKIPPED_ENVIRONMENTS + 1))
        return
    fi
    
    log_message "Processing source environment: $source_env_name"
    
    # Find corresponding destination environment
    local dest_env_data=$(find_dest_environment "$source_env_name")
    
    if [ -z "$dest_env_data" ]; then
        log_message "Warning: No corresponding destination environment found for $source_env_name"
        SKIPPED_ENVIRONMENTS=$((SKIPPED_ENVIRONMENTS + 1))
        return
    fi
    
    local dest_env_name=$(echo "$dest_env_data" | jq -r '.name')
    local dest_env_id=$(echo "$dest_env_data" | jq -r '.id')
    local source_env_id=$(echo "$source_env_data" | jq -r '.id')
    
    # Validate destination environment data
    if [ -z "$dest_env_name" ] || [ "$dest_env_name" = "null" ] || [ -z "$dest_env_id" ] || [ "$dest_env_id" = "null" ]; then
        log_message "ERROR: Invalid destination environment data for $source_env_name"
        log_message "Destination name: '$dest_env_name', ID: '$dest_env_id'"
        FAILED_COPIES=$((FAILED_COPIES + 1))
        return
    fi
    
    log_message "Found destination environment: $dest_env_name (ID: $dest_env_id)"
    
    # Copy team rolebindings
    if copy_all_environment_settings "$source_env_id" "$dest_env_id" "$source_env_name" "$dest_env_name"; then
        log_message "Successfully copied settings from $source_env_name to $dest_env_name"
        SUCCESSFUL_COPIES=$((SUCCESSFUL_COPIES + 1))
        
        log_summary "SUCCESS: $source_env_name -> $dest_env_name"
    else
        log_message "Failed to copy settings from $source_env_name to $dest_env_name"
        FAILED_COPIES=$((FAILED_COPIES + 1))
        
        log_summary "FAILED: $source_env_name -> $dest_env_name"
    fi
}

# Process each source environment
log_message "Processing source environments..."

# SAFETY: First, let's build a complete mapping preview before doing anything
MAPPING_PREVIEW=()
MAPPING_ERRORS=()

if [ "$INTERACTIVE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
    log_message "🤝 Starting interactive environment mapping..."
    echo ""
    echo "🤝 INTERACTIVE ENVIRONMENT MAPPING MODE"
    echo "======================================="
    echo "You will be asked to confirm each environment mapping individually."
    echo "Options: 'y' (yes), 'n' (no - specify custom), 'list' (show available destinations)"
    echo ""
    
    # Interactive processing - Process environments one by one
    # Create temporary file to store environment data
    temp_env_file="/tmp/source_envs_$$"
    echo "$SOURCE_ENVIRONMENTS" | jq -c '.' > "$temp_env_file"
    
    # Use exec to redirect stdin properly for the entire loop
    exec 3< "$temp_env_file"
    while IFS= read -r source_env_data <&3; do
        if [ -n "$source_env_data" ] && [ "$source_env_data" != "null" ]; then
            source_env_name=$(echo "$source_env_data" | jq -r '.name')
            
            # Skip empty names
            if [ -z "$source_env_name" ] || [ "$source_env_name" = "null" ]; then
                continue
            fi
            
            # Skip system namespaces
            if is_system_namespace "$source_env_name"; then
                echo "⏭️  Skipping system namespace: $source_env_name"
                continue
            fi
            
            echo ""
            echo "🔍 Processing environment: $source_env_name"
            
            # Find suggested destination environment
            dest_env_data=$(find_dest_environment "$source_env_name")
            
            if [ -z "$dest_env_data" ]; then
                echo ""
                echo "⚠️  No automatic match found for: $source_env_name"
                echo "Available destination environments:"
                echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" '.[] | select(.cluster[].id == $cluster) | .name' | sort | head -20 | sed 's/^/  - /'
                echo ""
                
                while true; do
                    echo -n "Enter destination environment name for '$source_env_name' (or 'skip' to skip): "
                    read -r custom_dest_name </dev/tty
                    
                    if [ "$custom_dest_name" = "skip" ]; then
                        echo "⏭️  Skipping environment: $source_env_name"
                        MAPPING_ERRORS+=("$source_env_name")
                        break
                    fi
                    
                    # Validate the custom destination environment exists
                    custom_dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$custom_dest_name" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
                    
                    if [ ! -z "$custom_dest_env" ] && [ "$custom_dest_env" != "null" ]; then
                        echo "✅ Manual mapping: $source_env_name → $custom_dest_name"
                        MAPPING_PREVIEW+=("$source_env_name|$custom_dest_name")
                        break
                    else
                        echo "❌ Error: Destination environment '$custom_dest_name' not found in cluster '$DEST_CLUSTER'"
                        echo "Please choose from the available environments listed above."
                        echo ""
                    fi
                done
            else
                suggested_dest_name=$(echo "$dest_env_data" | jq -r '.name')
                
                # Interactive confirmation - call function directly
                echo ""
                echo "🔍 ENVIRONMENT MAPPING CONFIRMATION"
                echo "======================================"
                echo "Source Environment: $source_env_name"
                echo "Suggested Destination: $suggested_dest_name"
                echo ""
                
                while true; do
                    echo -n "Do you want to copy settings from '$source_env_name' to '$suggested_dest_name'? (y/n/list): "
                    read -r response </dev/tty
                    
                    case "$response" in
                        [Yy]|[Yy][Ee][Ss]|"y"|"Y")
                            echo "✅ Confirmed: $source_env_name → $suggested_dest_name"
                            MAPPING_PREVIEW+=("$source_env_name|$suggested_dest_name")
                            break
                            ;;
                        [Nn]|[Nn][Oo]|"n"|"N")
                            echo ""
                            echo "❌ Mapping rejected. Please specify the correct destination environment."
                            echo ""
                            echo "Available destination environments:"
                            echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" '.[] | select(.cluster[0].id == $cluster) | .name' | sort | head -20 | sed 's/^/  - /'
                            echo ""
                            
                            while true; do
                                echo -n "Enter the correct destination environment name (or 'skip' to skip this environment): "
                                read -r custom_dest_name </dev/tty
                                
                                if [ "$custom_dest_name" = "skip" ]; then
                                    echo "⏭️  Skipping environment: $source_env_name"
                                    MAPPING_ERRORS+=("$source_env_name")
                                    break 2  # Break out of both loops
                                fi
                                
                                # Validate the custom destination environment exists
                                custom_dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$custom_dest_name" '.[] | select(.cluster[0].id == $cluster and .name == $name)')
                                
                                if [ ! -z "$custom_dest_env" ] && [ "$custom_dest_env" != "null" ]; then
                                    echo "✅ Custom mapping confirmed: $source_env_name → $custom_dest_name"
                                    MAPPING_PREVIEW+=("$source_env_name|$custom_dest_name")
                                    break 2  # Break out of both loops
                                else
                                    echo "❌ Error: Destination environment '$custom_dest_name' not found in cluster '$DEST_CLUSTER'"
                                    echo "Please choose from the available environments listed above."
                                    echo ""
                                fi
                            done
                            ;;
                        [Ll][Ii][Ss][Tt]|"list"|"LIST")
                            echo ""
                            echo "📋 Available destination environments in cluster '$DEST_CLUSTER':"
                            echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" '.[] | select(.cluster[0].id == $cluster) | .name' | sort | head -20 | sed 's/^/  - /'
                            echo ""
                            # Continue the loop to ask again
                            ;;
                        "")
                            echo "Please enter a response. Options: 'y' for yes, 'n' for no, 'list' to see available environments."
                            ;;
                        *)
                            echo "Invalid response: '$response'. Please answer 'y' for yes, 'n' for no, or 'list' to see available environments."
                            ;;
                    esac
                done
            fi
        fi
    done
    exec 3<&-  # Close file descriptor 3
    
    # Clean up temporary file
    rm -f "$temp_env_file"
else
log_message "🔍 Building environment mapping preview..."
echo ""
echo "🗺️  ENVIRONMENT MAPPING PREVIEW"
echo "================================"

while read -r source_env_data; do
    if [ -n "$source_env_data" ]; then
        source_env_name=$(echo "$source_env_data" | jq -r '.name')
            
            # Skip system namespaces
            if is_system_namespace "$source_env_name"; then
                echo "⏭️  Skipping system namespace: $source_env_name"
                continue
            fi
        
        # Find corresponding destination environment
            dest_env_data=$(find_dest_environment "$source_env_name")
        
        if [ -z "$dest_env_data" ]; then
            echo "❌ $source_env_name -> NO MATCH FOUND"
            MAPPING_ERRORS+=("$source_env_name")
        else
                dest_env_name=$(echo "$dest_env_data" | jq -r '.name')
            echo "✅ $source_env_name -> $dest_env_name"
            MAPPING_PREVIEW+=("$source_env_name|$dest_env_name")
        fi
    fi
done < <(echo "$SOURCE_ENVIRONMENTS" | jq -c '.')
fi

echo ""
echo "📊 MAPPING SUMMARY:"
echo "  ✅ Successful mappings: ${#MAPPING_PREVIEW[@]}"
echo "  ❌ Failed mappings: ${#MAPPING_ERRORS[@]}"

if [ ${#MAPPING_ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  ENVIRONMENTS WITH NO DESTINATION MATCH:"
    for error_env in "${MAPPING_ERRORS[@]}"; do
        echo "   - $error_env"
    done
    echo ""
    echo "🔍 These environments will be SKIPPED during migration"
fi

# Save environment mappings to JSON file
if [ "$DRY_RUN" = true ]; then
    if [ "$INTERACTIVE_MODE" = true ]; then
        save_environment_mappings "$MAPPING_FILE" "DRY-RUN-INTERACTIVE"
    else
        save_environment_mappings "$MAPPING_FILE" "DRY-RUN"
    fi
else
    if [ "$INTERACTIVE_MODE" = true ]; then
        save_environment_mappings "$MAPPING_FILE" "LIVE-INTERACTIVE"
    else
        save_environment_mappings "$MAPPING_FILE" "LIVE"
    fi
fi

echo ""

# Safety confirmation (unless auto-confirm is set or in interactive mode)
if [ "$AUTO_CONFIRM" != true ] && [ "$INTERACTIVE_MODE" != true ]; then
    if [ "$DRY_RUN" != true ]; then
        echo "⚠️  WARNING: This will make LIVE CHANGES to destination environment!"
        echo "🛡️  Recommendation: Run with --dry-run first to test"
        echo ""
    fi
    
    echo -n "Do you want to proceed with this mapping? (y/N): "
    read -r confirmation </dev/tty
    
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        log_message "Operation cancelled by user"
        echo "Operation cancelled. No changes made."
        exit 0
    fi
    
    log_message "User confirmed operation. Proceeding..."
elif [ "$INTERACTIVE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
    echo ""
    echo "🤝 Interactive mapping completed!"
    echo "📊 Final mapping summary:"
    echo "  ✅ Environments to process: ${#MAPPING_PREVIEW[@]}"
    echo "  ⏭️  Environments to skip: ${#MAPPING_ERRORS[@]}"
    echo ""
    
    if [ ${#MAPPING_PREVIEW[@]} -eq 0 ]; then
        echo "❌ No environments selected for processing. Exiting."
        exit 0
    fi
    
    echo "📋 CONFIRMED 1:1 ENVIRONMENT MAPPINGS:"
    echo "======================================"
    mapping_counter=1
    for mapping in "${MAPPING_PREVIEW[@]}"; do
        IFS='|' read -r source_env dest_env <<< "$mapping"
        printf "%2d. %-35s → %s\n" "$mapping_counter" "$source_env" "$dest_env"
        mapping_counter=$((mapping_counter + 1))
    done
    echo ""
    
    echo "⚠️  WARNING: This will make LIVE CHANGES to destination environment!"
    echo "🔧 Settings to be copied for EACH environment above:"
    echo "   • Resource Quotas & Limit Ranges"
    echo "   • Access Controls (Teams, Users, Roles)"
    echo "   • Labels & Owner Details"
    echo "   • Update Policies"
    echo "   • Kubernetes Resources (ConfigMaps, Secrets, etc.)"
    echo ""
    echo -n "Proceed with copying settings for the ${#MAPPING_PREVIEW[@]} confirmed mappings? (y/N): "
    read -r final_confirmation </dev/tty
    
    if [[ ! "$final_confirmation" =~ ^[Yy]$ ]]; then
        log_message "Operation cancelled by user"
        echo "Operation cancelled. No changes made."
        exit 0
    fi
    
    log_message "Interactive mapping confirmed. Proceeding with ${#MAPPING_PREVIEW[@]} environments..."
elif [ "$INTERACTIVE_MODE" = true ] && [ "$DRY_RUN" = true ]; then
    echo ""
    echo "🔍 DRY-RUN with Interactive Mode: Showing automatic mappings only"
    echo "ℹ️  In DRY-RUN mode, interactive confirmation is skipped"
    echo "ℹ️  Run with --live for interactive confirmation of each mapping"
fi

echo ""
if [ "$DRY_RUN" = true ]; then
    echo "🔍 Starting DRY-RUN environment processing..."
else
    echo "🚀 Starting LIVE environment processing..."
fi

if [ "$INTERACTIVE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
    echo "🤝 Processing ${#MAPPING_PREVIEW[@]} interactively confirmed environment mappings..."
elif [ "$INTERACTIVE_MODE" = true ] && [ "$DRY_RUN" = true ]; then
    echo "🔍 DRY-RUN: Showing ${#MAPPING_PREVIEW[@]} automatically detected environment mappings..."
else
    echo "🤖 Processing ${#MAPPING_PREVIEW[@]} automatically detected environment mappings..."
fi
echo ""

# Now process the confirmed mappings
for mapping in "${MAPPING_PREVIEW[@]}"; do
    IFS='|' read -r source_env_name dest_env_name <<< "$mapping"
    
    # Get the source environment data again
    source_env_data=$(echo "$SOURCE_ENVIRONMENTS" | jq -c --arg name "$source_env_name" '. | select(.name == $name)')
    
    copy_environment_settings "$source_env_name" "$source_env_data"
done

# Log final summary
log_message "Cross-environment restoration completed"
log_message "Total environments processed: $TOTAL_ENVIRONMENTS"
log_message "Successful copies: $SUCCESSFUL_COPIES"
log_message "Skipped environments: $SKIPPED_ENVIRONMENTS"
log_message "Failed copies: $FAILED_COPIES"

log_summary "----------------------------------------"
log_summary "FINAL SUMMARY:"
log_summary "Total environments processed: $TOTAL_ENVIRONMENTS"
log_summary "Successful copies: $SUCCESSFUL_COPIES"
log_summary "Skipped environments: $SKIPPED_ENVIRONMENTS"
log_summary "Failed copies: $FAILED_COPIES"

echo ""
echo "📁 OUTPUT FILES GENERATED:"
echo "  📋 Detailed Log: $LOG_FILE"
echo "  📊 Summary Log: $SUMMARY_FILE" 
echo "  🗺️  Environment Mappings: $MAPPING_FILE"
echo ""
echo "💡 LOG FILE CONTENTS:"
if [ "$DRY_RUN" = true ]; then
    echo "  🔍 DRY-RUN mode - All operations logged with [DRY-RUN] prefix"
    echo "  📝 Shows what WOULD be done without making changes"
else
    echo "  🚀 LIVE mode - All actual operations and API calls logged"
    echo "  📝 Complete record of all environment settings copied"
fi
echo "  🕒 Timestamped entries for audit trail"
echo "  ❌ Error details for troubleshooting"
echo ""

if [ $FAILED_COPIES -gt 0 ]; then
    log_message "WARNING: Some environment settings failed to copy. Check the logs for details."
    echo "❌ Migration completed with errors. Check the files above for details."
    exit 1
else
    log_message "All environment settings copied successfully!"
    if [ "$DRY_RUN" = true ]; then
        echo "✅ DRY-RUN completed successfully! Review the files above before running with --live"
    else
        echo "✅ LIVE migration completed successfully! All settings have been copied."
    fi
    exit 0
fi 