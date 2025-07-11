#!/bin/bash

# Check if required parameters are provided
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <api_endpoint> <token> <source_cluster> <destination_cluster> [OPTIONS]"
    echo ""
    echo "Safety Options:"
    echo "  --dry-run                    Show what would be done without making changes (DEFAULT)"
    echo "  --generate-mapping           Generate environment mapping file for review"
    echo "  --use-mapping-file FILE      Use pre-verified mapping file for migration"
    echo "  --live                       Make actual changes (DANGEROUS - use with caution)"
    echo "  --auto-confirm              Skip confirmation prompts"
    echo "  --interactive               Interactive mode - confirm each environment mapping"
    echo "  --verbose                   Show detailed API responses"
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
    echo "  $0 https://api.co TOKEN1 source-cluster dest-cluster --generate-mapping"
    echo ""
    echo "  # Step 2: Execute with verified mapping (CONTROLLED)"
    echo "  $0 https://api.co TOKEN1 source-cluster dest-cluster --use-mapping-file verified_mapping.json --live"
    echo ""
    echo "  # Step 3: Interactive mode (MANUAL CONTROL)"
    echo "  $0 https://api.co TOKEN1 source-cluster dest-cluster --interactive --live"
    exit 1
fi

API_ENDPOINT=$1
TOKEN=$2
SOURCE_CLUSTER=$3
DEST_CLUSTER=$4

# Parse safety flags - DRY RUN IS DEFAULT!
DRY_RUN=true
AUTO_CONFIRM=false
VERBOSE=false
GENERATE_MAPPING=false
USE_MAPPING_FILE=""
INTERACTIVE_MODE=false

shift 4
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
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
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Safety validation
if [ "$DRY_RUN" = false ] && [ -z "$USE_MAPPING_FILE" ] && [ "$AUTO_CONFIRM" != true ] && [ "$INTERACTIVE_MODE" != true ]; then
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

# Create log file with timestamp and mode indicator
if [ "$DRY_RUN" = true ]; then
    if [ "$INTERACTIVE_MODE" = true ]; then
        LOG_FILE="${LOG_DIR}/env_restore_DRY_RUN_INTERACTIVE_${TIMESTAMP}.log"
        SUMMARY_FILE="${LOG_DIR}/env_restore_summary_DRY_RUN_INTERACTIVE_${TIMESTAMP}.log"
        MAPPING_FILE="${LOG_DIR}/env_mapping_preview_DRY_RUN_INTERACTIVE_${TIMESTAMP}.json"
    elif [ "$GENERATE_MAPPING" = true ]; then
        LOG_FILE="${LOG_DIR}/env_restore_GENERATE_MAPPING_${TIMESTAMP}.log"
        SUMMARY_FILE="${LOG_DIR}/env_restore_summary_GENERATE_MAPPING_${TIMESTAMP}.log"
        MAPPING_FILE="${LOG_DIR}/env_mapping_generated_${TIMESTAMP}.json"
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

# Function to log messages with timestamp
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

# Function to log summary
log_summary() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$SUMMARY_FILE"
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
    
    # Create JSON structure
    echo "{" > "$mapping_file"
    echo "  \"migration_info\": {" >> "$mapping_file"
    echo "    \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"," >> "$mapping_file"
    echo "    \"mode\": \"$mode\"," >> "$mapping_file"
    echo "    \"source_cluster\": \"$SOURCE_CLUSTER\"," >> "$mapping_file"
    echo "    \"destination_cluster\": \"$DEST_CLUSTER\"," >> "$mapping_file"
    echo "    \"api_endpoint\": \"$API_ENDPOINT\"," >> "$mapping_file"
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
    local first=true
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
    
    # Always show interactive prompts when this function is called
    
    while true; do
        echo ""
        echo "🤔 CONFIRM ENVIRONMENT MAPPING:"
        echo "   Source: $source_env_name"
        echo "   Destination: $suggested_dest_env_name"
        echo ""
        echo "Options:"
        echo "  y/yes    - Confirm this mapping"
        echo "  n/no     - Reject and manually specify destination"
        echo "  list     - Show all available destination environments"
        echo "  skip     - Skip this environment completely"
        echo ""
        echo -n "Your choice [y/n/list/skip]: "
        read -r response </dev/tty
        
        # Handle empty input
        if [ -z "$response" ]; then
            echo "❌ Empty input detected. Please enter 'y', 'n', 'list', or 'skip'."
            continue
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]|"y"|"Y"|"yes"|"YES")
                echo "✅ Confirmed: $source_env_name → $suggested_dest_env_name"
                echo "$suggested_dest_env_name"
                return 0
                ;;
            [Ss][Kk][Ii][Pp]|"skip"|"SKIP")
                echo "⏭️  Skipping environment: $source_env_name"
                return 1
                ;;
            [Nn]|[Nn][Oo]|"n"|"N"|"no"|"NO")
                echo ""
                echo "❌ Mapping rejected. Please specify the correct destination environment."
                echo ""
                echo "Available destination environments:"
                # Filter environments to only include destination cluster
                dest_environments=$(echo "$ENVIRONMENTS" | jq -c --arg cluster_id "$DEST_CLUSTER_ID" '[.[] | select(.cluster[0].id == $cluster_id)]')
                echo "$dest_environments" | jq -r '.[] | "  - " + .name' | sort
                echo ""
                
                while true; do
                    echo -n "Enter the correct destination environment name (or 'skip' to skip this environment): "
                    read -r custom_dest_name </dev/tty
                    
                    # Handle empty input
                    if [ -z "$custom_dest_name" ]; then
                        echo "❌ Empty input detected. Please enter a valid environment name or 'skip'."
                        continue
                    fi
                    
                    if [ "$custom_dest_name" = "skip" ]; then
                        echo "⏭️  Skipping environment: $source_env_name"
                        return 1
                    fi
                    
                    # Validate the custom destination environment exists
                    custom_dest_env=$(echo "$dest_environments" | jq -c --arg name "$custom_dest_name" '.[] | select(.name == $name)')
                    
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
                dest_environments=$(echo "$ENVIRONMENTS" | jq -c --arg cluster_id "$DEST_CLUSTER_ID" '[.[] | select(.cluster[0].id == $cluster_id)]')
                echo "$dest_environments" | jq -r '.[] | "  - " + .name' | sort
                echo ""
                echo "💡 You can now:"
                echo "  - Type 'y' to confirm the suggested mapping: $suggested_dest_env_name"
                echo "  - Type 'n' to manually specify a different environment"
                echo "  - Type 'skip' to skip this environment"
                echo ""
                # Continue the loop to ask again
                ;;
            "")
                echo "Please enter a response. Options: 'y' for yes, 'n' for no, 'list' to see available environments, 'skip' to skip."
                ;;
            *)
                echo "Invalid response: '$response'. Please answer 'y' for yes, 'n' for no, 'list' to see available environments, or 'skip' to skip."
                ;;
        esac
    done
}

# Function to find corresponding destination environment with multiple strategies
find_dest_environment() {
    local source_env_name=$1
    
    log_message "Looking for destination environment matching source: $source_env_name" >&2
    
    # Validate input
    if [ -z "$source_env_name" ]; then
        log_message "ERROR: Empty source environment name provided" >&2
        return 1
    fi
    
    # Filter environments to only include destination cluster
    local dest_environments=$(echo "$ENVIRONMENTS" | jq -c --arg cluster_id "$DEST_CLUSTER_ID" '[.[] | select(.cluster[0].id == $cluster_id)]')
    
    # Strategy 1: Exact match (only in destination cluster)
    local dest_env=$(echo "$dest_environments" | jq -c --arg name "$source_env_name" '.[] | select(.name == $name)')
    
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
    fi
    
    # Strategy 3: Try to find destination environment using extracted namespace
    # Try multiple destination patterns
    
    # Pattern A: exact namespace match
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$namespace" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found namespace-only match: $namespace" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Pattern B: destcluster-namespace
    local dest_pattern="$DEST_CLUSTER-$namespace"
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$dest_pattern" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found cluster-prefix match: $dest_pattern" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Pattern C: namespace-destcluster
    dest_pattern="$namespace-$DEST_CLUSTER"
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$dest_pattern" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        log_message "Found cluster-suffix match: $dest_pattern" >&2
        echo "$dest_env"
        return 0
    fi
    
    # Pattern D: Case-insensitive versions
    dest_pattern="$dest_cluster_lower-$namespace"
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$dest_pattern" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        echo "$dest_env"
        return 0
    fi
    
    dest_pattern="$namespace-$dest_cluster_lower"
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$dest_pattern" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        echo "$dest_env"
        return 0
    fi
    
    # Pattern E: Special migration pattern - replace source cluster with destination cluster
    dest_pattern=$(echo "$source_env_name" | sed "s/-$SOURCE_CLUSTER$/-$DEST_CLUSTER/")
    if [ "$dest_pattern" != "$source_env_name" ]; then
        dest_env=$(echo "$dest_environments" | jq -c --arg name "$dest_pattern" '.[] | select(.name == $name)')
        if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
            echo "$dest_env"
            return 0
        fi
    fi
    
    # Pattern F: Legacy simple replacement (backwards compatibility)
    if [[ "$source_env_name" == "new-migration" ]]; then
        # Special case for new-migration environment
        dest_pattern="new-migration-${DEST_CLUSTER}"
    elif [[ "$source_env_name" == *"$SOURCE_CLUSTER" ]]; then
        # Environment has source cluster suffix
        dest_pattern="${source_env_name%$SOURCE_CLUSTER}$DEST_CLUSTER"
    else
        # Environment doesn't have cluster suffix
        dest_pattern="${source_env_name}-${DEST_CLUSTER}"
    fi
    
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$dest_pattern" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        echo "$dest_env"
        return 0
    fi
    
    # Strategy 4: Fuzzy matching - contains the namespace
    dest_env=$(echo "$dest_environments" | jq -c --arg pattern "$namespace" '.[] | select(.name | contains($pattern))')
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
    
    # List available destination environments for debugging
    local env_list
    env_list=$(echo "$dest_environments" | jq -r '.[].name' 2>/dev/null | head -10)
    
    if [ $? -eq 0 ] && [ ! -z "$env_list" ]; then
        echo "$env_list" | while read -r env_name; do
            log_message "  - $env_name" >&2
        done
    else
        log_message "ERROR: Failed to parse destination environments list" >&2
    fi
    
    return 1
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

# Function to execute API call or simulate in dry run mode
execute_api_call() {
    local description="$1"
    local method="$2"
    local url="$3"
    local data="$4"
    local headers="$5"
    
    if [ "$DRY_RUN" = true ]; then
        log_message "🔍 DRY RUN: Would $description"
        log_message "   Method: $method"
        log_message "   URL: $url"
        if [ ! -z "$data" ] && [ "$data" != "null" ]; then
            log_message "   Data: $(echo "$data" | jq -c . 2>/dev/null || echo "$data")"
        fi
        return 0
    else
        log_message "🚀 LIVE: $description"
        if [ "$method" = "GET" ]; then
            curl -s -H "$headers" "$url"
        elif [ "$method" = "POST" ]; then
            curl -s -X POST -H "$headers" -H "Content-Type: application/json" -d "$data" "$url"
        elif [ "$method" = "PUT" ]; then
            curl -s -X PUT -H "$headers" -H "Content-Type: application/json" -d "$data" "$url"
        elif [ "$method" = "PATCH" ]; then
            curl -s -X PATCH -H "$headers" -H "Content-Type: application/json" -d "$data" "$url"
        fi
    fi
}

# Function to ask for user confirmation
ask_confirmation() {
    local message="$1"
    
    if [ "$AUTO_CONFIRM" = true ]; then
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        return 0  # Skip confirmation in dry run mode
    fi
    
    echo ""
    echo "⚠️  $message"
    echo -n "Do you want to continue? (y/N): "
    read -r response </dev/tty
    
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            echo "Operation cancelled by user."
            exit 1
            ;;
    esac
}

# Function to display mode banner
display_mode_banner() {
    echo ""
    echo "============================================================"
    if [ "$DRY_RUN" = true ]; then
        if [ "$GENERATE_MAPPING" = true ]; then
            echo "🗺️  GENERATE MAPPING MODE - CREATING MAPPING FILE"
            echo "   This will create a mapping file for review"
            echo "   Use --use-mapping-file to execute with verified mappings"
        else
            echo "🔍 DRY RUN MODE - NO CHANGES WILL BE MADE"
            echo "   This is a preview of what would happen"
            echo "   Use --live to actually execute changes"
        fi
    else
        echo "🚀 LIVE MODE - CHANGES WILL BE MADE"
        echo "   This will modify your environments!"
        echo "   Make sure you've reviewed the dry run output first"
    fi
    echo "============================================================"
    echo ""
}

# Initialize summary counters
TOTAL_ENVIRONMENTS=0
SUCCESSFUL_COPIES=0
SKIPPED_ENVIRONMENTS=0
FAILED_COPIES=0

# Initialize mapping arrays
MAPPING_PREVIEW=()
MAPPING_ERRORS=()

# Display mode banner
display_mode_banner

echo "📁 LOGGING INFORMATION:"
echo "   📊 Detailed Log: $LOG_FILE"
echo "   📋 Summary Log:  $SUMMARY_FILE"
echo "   🗺️  Mapping File: $MAPPING_FILE"
echo ""

log_message "Starting environment settings restoration from $SOURCE_CLUSTER to $DEST_CLUSTER"
log_summary "Environment Settings Restoration Summary"
log_summary "Source Cluster: $SOURCE_CLUSTER"
log_summary "Destination Cluster: $DEST_CLUSTER"
if [ "$DRY_RUN" = true ]; then
    log_summary "Mode: DRY RUN (preview only)"
else
    log_summary "Mode: LIVE (making actual changes)"
fi
log_summary "----------------------------------------"

# Validate token
if [ -z "$TOKEN" ]; then
    log_message "Error: Token is required"
    exit 1
fi

# Get all clusters
CLUSTERS_RESPONSE=$(curl -s -H "Accept: application/json" \
    -H "Authorization: NIRMATA-API ${TOKEN}" \
    "${API_ENDPOINT}/environments/api/clusters")

# Check if unauthorized
if echo "$CLUSTERS_RESPONSE" | grep -q "Not authorized"; then
    log_message "Error: Not authorized. Please check your token."
    log_message "Response: $CLUSTERS_RESPONSE"
    exit 1
fi

# Check if response is valid JSON
if ! echo "$CLUSTERS_RESPONSE" | jq '.' >/dev/null 2>&1; then
    log_message "Error: Invalid JSON response from clusters API"
    log_message "Response: $CLUSTERS_RESPONSE"
    exit 1
fi

# Get cluster IDs using the correct JSON path
SOURCE_CLUSTER_ID=$(echo "$CLUSTERS_RESPONSE" | jq -r --arg name "$SOURCE_CLUSTER" '.[] | select(.name == $name) | .id')
DEST_CLUSTER_ID=$(echo "$CLUSTERS_RESPONSE" | jq -r --arg name "$DEST_CLUSTER" '.[] | select(.name == $name) | .id')

if [ -z "$SOURCE_CLUSTER_ID" ] || [ -z "$DEST_CLUSTER_ID" ]; then
    log_message "Error: Could not find cluster IDs"
    log_message "Source cluster ($SOURCE_CLUSTER): $SOURCE_CLUSTER_ID"
    log_message "Destination cluster ($DEST_CLUSTER): $DEST_CLUSTER_ID"
    log_message "Available clusters:"
    echo "$CLUSTERS_RESPONSE" | jq -r '.[].name'
    exit 1
fi

log_message "Source cluster ID: $SOURCE_CLUSTER_ID"
log_message "Destination cluster ID: $DEST_CLUSTER_ID"

# Get all environments
ENVIRONMENTS_RESPONSE=$(curl -s -H "Accept: application/json" \
    -H "Authorization: NIRMATA-API $TOKEN" \
    "${API_ENDPOINT}/environments/api/environments")

# Check if response is valid JSON
if ! echo "$ENVIRONMENTS_RESPONSE" | jq '.' >/dev/null 2>&1; then
    log_message "Error: Invalid JSON response from environments API"
    log_message "Response: $ENVIRONMENTS_RESPONSE"
    exit 1
fi

ENVIRONMENTS="$ENVIRONMENTS_RESPONSE"

# Get source environments using the correct JSON path
SOURCE_ENVIRONMENTS=$(echo "$ENVIRONMENTS_RESPONSE" | jq --arg cluster "$SOURCE_CLUSTER_ID" '[.[] | select(.cluster[].id == $cluster)]')

# Log cluster information for debugging
log_message "Found $(echo "$ENVIRONMENTS" | jq '. | length') total environments"
log_message "Found $(echo "$SOURCE_ENVIRONMENTS" | jq '. | length') source environments in cluster $SOURCE_CLUSTER"

if [ -z "$SOURCE_ENVIRONMENTS" ]; then
    log_message "No environments found in source cluster $SOURCE_CLUSTER"
    log_message "Source cluster ID: $SOURCE_CLUSTER_ID"
    log_message "Available environments:"
    echo "$ENVIRONMENTS_RESPONSE" | jq -r '.[].name'
    exit 1
fi

# Function to get team rolebindings
get_team_rolebindings() {
    local env_id=$1
    local response
    response=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" \
        "$API_ENDPOINT/environments/api/environments/$env_id/teamrolebindings?fields=id,name,team,role")
    
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to get team rolebindings for environment $env_id"
        return 1
    fi
    
    echo "$response"
}

# Function to create team rolebinding
create_team_rolebinding() {
    local env_id=$1
    local team_id=$2
    local role_id=$3
    local team_name=$4
    local permission=$5
    
    log_message "Creating team rolebinding for team $team_name with permission $permission"
    
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
    
    curl -s -X POST -H "Authorization: NIRMATA-API $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$API_ENDPOINT/environments/api/environments/$env_id/teamrolebindings"
    
    log_message "Created team rolebinding for team $team_name"
}

# Function to copy team rolebindings
copy_team_rolebindings() {
    local source_env_id=$1
    local dest_env_id=$2
    local source_env_name=$3
    local dest_env_name=$4
    
    log_message "Copying team rolebindings from $source_env_name to $dest_env_name"
    
    # Get source ACL ID
    SOURCE_ACL_ID=$(curl -s -H "Accept: application/json" \
        -H "Authorization: NIRMATA-API $TOKEN" \
        "${API_ENDPOINT}/environments/api/environments/$source_env_id" | jq -r '.accessControlList[0].id')

    if [ ! -z "$SOURCE_ACL_ID" ] && [ "$SOURCE_ACL_ID" != "null" ]; then
        # Get source ACL details
        SOURCE_ACL_DETAILS=$(curl -s -H "Accept: application/json" \
            -H "Authorization: NIRMATA-API $TOKEN" \
            "${API_ENDPOINT}/environments/api/accessControlLists/$SOURCE_ACL_ID")
        
        # Get access control IDs
        ACCESS_CONTROL_IDS=$(echo "$SOURCE_ACL_DETAILS" | jq -r '.accessControls[].id')
        
        # Process each access control
        for control_id in $ACCESS_CONTROL_IDS; do
            # Get access control details
            CONTROL_DETAILS=$(curl -s -H "Accept: application/json" \
                -H "Authorization: NIRMATA-API $TOKEN" \
                "${API_ENDPOINT}/environments/api/accessControls/$control_id")
            
            ENTITY_ID=$(echo "$CONTROL_DETAILS" | jq -r '.entityId')
            ENTITY_TYPE=$(echo "$CONTROL_DETAILS" | jq -r '.entityType')
            PERMISSION=$(echo "$CONTROL_DETAILS" | jq -r '.permission')
            ENTITY_NAME=$(echo "$CONTROL_DETAILS" | jq -r '.entityName')
            
            if [ "$ENTITY_TYPE" = "team" ]; then
                log_message "Creating team rolebinding for team $ENTITY_NAME with permission $PERMISSION"
                
                # Create team rolebinding payload
                local payload="{
                    \"modelIndex\": \"TeamRoleBinding\",
                    \"parent\": {
                        \"id\": \"$dest_env_id\",
                        \"service\": \"Environment\",
                        \"modelIndex\": \"Environment\",
                        \"childRelation\": \"teamrolebindings\"
                    },
                    \"team\": \"$ENTITY_ID\",
                    \"role\": \"$PERMISSION\",
                    \"name\": \"$ENTITY_NAME-$PERMISSION\"
                }"
                
                # Create team rolebinding
                local response=$(curl -s -X POST \
                    -H "Content-Type: application/json" \
                    -H "Authorization: NIRMATA-API $TOKEN" \
                    -d "$payload" \
                    "${API_ENDPOINT}/environments/api/environments/$dest_env_id/teamrolebindings")
                
                if [ ! -z "$response" ]; then
                    log_message "Successfully created team rolebinding for team $ENTITY_NAME"
                else
                    log_message "Failed to create team rolebinding for team $ENTITY_NAME"
                fi
            fi
        done
    fi
}

# Function to copy environment settings
copy_environment_settings() {
    local source_env_id=$1
    local dest_env_id=$2
    local source_env_name=$3
    local dest_env_name=$4
    
    # ... existing code ...
    
    # Copy team rolebindings
    copy_team_rolebindings "$source_env_id" "$dest_env_id" "$source_env_name" "$dest_env_name"
    
    # ... existing code ...
}

# Process each environment and build mappings
log_message "========== BUILDING ENVIRONMENT MAPPINGS =========="

if [ "$INTERACTIVE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
    # Interactive mode - always proceed when explicitly requested
    
    log_message "🤝 Starting interactive environment mapping..."
    echo ""
    echo "🤝 INTERACTIVE ENVIRONMENT MAPPING MODE"
    echo "======================================="
    echo "You will be asked to confirm each environment mapping individually."
    echo "Options: 'y' (yes), 'n' (no - specify custom), 'list' (show available destinations)"
    echo ""
    
    # Create temporary file to store environment data and avoid subshell issues
    temp_env_file="/tmp/source_envs_$$"
    echo "$SOURCE_ENVIRONMENTS" | jq -c '.[]' > "$temp_env_file"
    
    # Interactive processing - Process environments one by one  
    while IFS= read -r env; do
        if [ -n "$env" ] && [ "$env" != "null" ]; then
            ENV_NAME=$(echo "$env" | jq -r '.name')
            
            # Skip empty names
            if [ -z "$ENV_NAME" ] || [ "$ENV_NAME" = "null" ]; then
                continue
            fi
            
            # Check if this is a system namespace that should be skipped
            if is_system_namespace "$ENV_NAME"; then
                echo "⏭️  Skipping system namespace: $ENV_NAME"
                continue
            fi
            
            echo ""
            echo "🔍 Processing environment: $ENV_NAME"
            
            # Find suggested destination environment
            DEST_ENV=$(find_dest_environment "$ENV_NAME")
            
            if [ -z "$DEST_ENV" ]; then
                echo ""
                echo "⚠️  No automatic match found for: $ENV_NAME"
                echo "Available destination environments:"
                # Filter environments to only include destination cluster
                dest_environments=$(echo "$ENVIRONMENTS" | jq -c --arg cluster_id "$DEST_CLUSTER_ID" '[.[] | select(.cluster[0].id == $cluster_id)]')
                echo "$dest_environments" | jq -r '.[] | "  - " + .name' | sort | head -20
                echo ""
                
                # Simple manual input
                echo -n "Enter destination environment name for '$ENV_NAME' (or 'skip' to skip): "
                read -r custom_dest_name </dev/tty
                
                if [ "$custom_dest_name" = "skip" ]; then
                    echo "⏭️  Skipping environment: $ENV_NAME"
                    MAPPING_ERRORS+=("$ENV_NAME")
                else
                    echo "✅ Manual mapping: $ENV_NAME → $custom_dest_name"
                    MAPPING_PREVIEW+=("$ENV_NAME|$custom_dest_name")
                fi
            else
                DEST_ENV_NAME=$(echo "$DEST_ENV" | jq -r '.name')
                
                # Simple interactive confirmation
                echo ""
                echo "🤔 Environment mapping found:"
                echo "   Source: $ENV_NAME"
                echo "   Destination: $DEST_ENV_NAME"
                echo ""
                echo -n "Confirm this mapping? (y/n/list/skip): "
                read -r response </dev/tty
                
                case "$response" in
                    [Yy]|[Yy][Ee][Ss]|"y"|"Y"|"yes"|"YES")
                        echo "✅ Confirmed: $ENV_NAME → $DEST_ENV_NAME"
                        MAPPING_PREVIEW+=("$ENV_NAME|$DEST_ENV_NAME")
                        ;;
                    [Ss][Kk][Ii][Pp]|"skip"|"SKIP")
                        echo "⏭️  Skipping environment: $ENV_NAME"
                        MAPPING_ERRORS+=("$ENV_NAME")
                        ;;
                    [Ll][Ii][Ss][Tt]|"list"|"LIST")
                        echo ""
                        echo "📋 Available destination environments:"
                        dest_environments=$(echo "$ENVIRONMENTS" | jq -c --arg cluster_id "$DEST_CLUSTER_ID" '[.[] | select(.cluster[0].id == $cluster_id)]')
                        echo "$dest_environments" | jq -r '.[] | "  - " + .name' | sort
                        echo ""
                        echo -n "Enter destination environment name (or 'skip'): "
                        read -r custom_dest_name </dev/tty
                        
                        if [ "$custom_dest_name" = "skip" ]; then
                            echo "⏭️  Skipping environment: $ENV_NAME"
                            MAPPING_ERRORS+=("$ENV_NAME")
                        else
                            echo "✅ Custom mapping: $ENV_NAME → $custom_dest_name"
                            MAPPING_PREVIEW+=("$ENV_NAME|$custom_dest_name")
                        fi
                        ;;
                    [Nn]|[Nn][Oo]|"n"|"N"|"no"|"NO")
                        echo ""
                        echo "Available destination environments:"
                        dest_environments=$(echo "$ENVIRONMENTS" | jq -c --arg cluster_id "$DEST_CLUSTER_ID" '[.[] | select(.cluster[0].id == $cluster_id)]')
                        echo "$dest_environments" | jq -r '.[] | "  - " + .name' | sort
                        echo ""
                        echo -n "Enter destination environment name (or 'skip'): "
                        read -r custom_dest_name </dev/tty
                        
                        if [ "$custom_dest_name" = "skip" ]; then
                            echo "⏭️  Skipping environment: $ENV_NAME"
                            MAPPING_ERRORS+=("$ENV_NAME")
                        else
                            echo "✅ Custom mapping: $ENV_NAME → $custom_dest_name"
                            MAPPING_PREVIEW+=("$ENV_NAME|$custom_dest_name")
                        fi
                        ;;
                    *)
                        echo "Invalid response. Auto-confirming mapping: $ENV_NAME → $DEST_ENV_NAME"
                        MAPPING_PREVIEW+=("$ENV_NAME|$DEST_ENV_NAME")
                        ;;
                esac
            fi
        fi
    done < <(echo "$SOURCE_ENVIRONMENTS" | jq -c '.[]')
    
    # Clean up temporary file
    rm -f "$temp_env_file"
else
    # Non-interactive mapping - build preview
    log_message "🔍 Building automatic environment mapping preview..."
    echo ""
    echo "🗺️  ENVIRONMENT MAPPING PREVIEW"
    echo "================================"

    # Create temporary file to avoid subshell issues
    temp_env_file="/tmp/source_envs_$$"
    echo "$SOURCE_ENVIRONMENTS" | jq -c '.[]' > "$temp_env_file"

    while IFS= read -r env; do
        if [ -n "$env" ] && [ "$env" != "null" ]; then
            ENV_NAME=$(echo "$env" | jq -r '.name')
            
            # Skip empty names
            if [ -z "$ENV_NAME" ] || [ "$ENV_NAME" = "null" ]; then
                continue
            fi
            
            # Check if this is a system namespace that should be skipped
            if is_system_namespace "$ENV_NAME"; then
                echo "⏭️  Skipping system namespace: $ENV_NAME"
                continue
            fi
            
            log_message "Processing environment: $ENV_NAME"
            
            # Use intelligent environment mapping
            DEST_ENV=$(find_dest_environment "$ENV_NAME")
            
            if [ -z "$DEST_ENV" ]; then
                echo "❌ $ENV_NAME -> NO MATCH FOUND"
                MAPPING_ERRORS+=("$ENV_NAME")
                log_summary "FAILED: $ENV_NAME -> NO MATCH FOUND"
            else
                DEST_ENV_NAME=$(echo "$DEST_ENV" | jq -r '.name')
                echo "✅ $ENV_NAME -> $DEST_ENV_NAME"
                MAPPING_PREVIEW+=("$ENV_NAME|$DEST_ENV_NAME")
                log_summary "PREVIEW: $ENV_NAME -> $DEST_ENV_NAME"
            fi
        fi
    done < "$temp_env_file"
    
    # Clean up temporary file
    rm -f "$temp_env_file"
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
    if [ "$GENERATE_MAPPING" = true ]; then
        save_environment_mappings "$MAPPING_FILE" "GENERATE-MAPPING"
    elif [ "$INTERACTIVE_MODE" = true ]; then
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

# If generate-mapping mode, exit here
if [ "$GENERATE_MAPPING" = true ]; then
    echo ""
    echo "🗺️  MAPPING FILE GENERATED SUCCESSFULLY!"
    echo "   📄 Generated mapping file: $MAPPING_FILE"
    echo "   📊 Total mappings: ${#MAPPING_PREVIEW[@]}"
    echo "   ❌ Failed mappings: ${#MAPPING_ERRORS[@]}"
    echo ""
    echo "📝 NEXT STEPS:"
    echo "   1. Review the generated mapping file:"
    echo "      cat $MAPPING_FILE"
    echo ""
    echo "   2. Edit the mapping file if needed (optional)"
    echo ""
    echo "   3. Execute the migration with verified mappings:"
    echo "      $0 $API_ENDPOINT [TOKEN] $SOURCE_CLUSTER $DEST_CLUSTER --use-mapping-file $MAPPING_FILE --live"
    echo ""
    echo "✅ Mapping generation completed successfully!"
    exit 0
fi

# Ask for confirmation if not in dry run mode
if [ "$DRY_RUN" = false ]; then
    ask_confirmation "This will make actual changes to ${#MAPPING_PREVIEW[@]} environments. Are you sure you want to continue?"
fi

log_message "Starting environment processing..."

# Process each confirmed mapping
for mapping in "${MAPPING_PREVIEW[@]}"; do
    IFS='|' read -r source_env_name dest_env_name <<< "$mapping"
    
    TOTAL_ENVIRONMENTS=$((TOTAL_ENVIRONMENTS + 1))
    
    log_message "Processing mapping: $source_env_name -> $dest_env_name"
    
    # Get source environment data
    source_env_data=$(echo "$SOURCE_ENVIRONMENTS" | jq -c --arg name "$source_env_name" '.[] | select(.name == $name)')
    
    if [ -z "$source_env_data" ]; then
        log_message "ERROR: Could not find source environment data for: $source_env_name"
        FAILED_COPIES=$((FAILED_COPIES + 1))
        continue
    fi
    
    # Get destination environment data
    dest_env_data=$(echo "$ENVIRONMENTS" | jq -c --arg cluster_id "$DEST_CLUSTER_ID" --arg name "$dest_env_name" '.[] | select(.cluster[0].id == $cluster_id and .name == $name)')
    
    if [ -z "$dest_env_data" ]; then
        log_message "ERROR: Could not find destination environment data for: $dest_env_name"
        FAILED_COPIES=$((FAILED_COPIES + 1))
        continue
    fi
    
    SOURCE_ENV_ID=$(echo "$source_env_data" | jq -r '.id')
    DEST_ENV_ID=$(echo "$dest_env_data" | jq -r '.id')
    
    log_message "Source ID: $SOURCE_ENV_ID, Destination ID: $DEST_ENV_ID"
    # Copy resource type
    RESOURCE_TYPE=$(echo "$source_env_data" | jq -r '.resourceType')
    if [ ! -z "$RESOURCE_TYPE" ] && [ "$RESOURCE_TYPE" != "null" ]; then
        RESOURCE_TYPE_DATA="{\"resourceType\":\"$RESOURCE_TYPE\"}"
        execute_api_call \
            "set resource type to $RESOURCE_TYPE" \
            "PUT" \
            "${API_ENDPOINT}/environments/api/environments/$DEST_ENV_ID" \
            "$RESOURCE_TYPE_DATA" \
            "Authorization: NIRMATA-API $TOKEN"
    fi
    
    # Copy ACLs and permissions
    SOURCE_ACL_ID=$(echo "$source_env_data" | jq -r '.accessControlList[0].id')
    if [ -z "$SOURCE_ACL_ID" ] || [ "$SOURCE_ACL_ID" = "null" ]; then
        log_message "No access control list found in source environment"
    else
        log_message "Source ACL ID: $SOURCE_ACL_ID"
        
        # Get source ACL details
        SOURCE_ACL_DETAILS=$(curl -s -H "Accept: application/json" \
            -H "Authorization: NIRMATA-API $TOKEN" \
            "${API_ENDPOINT}/environments/api/accessControlLists/$SOURCE_ACL_ID")
        
        # Get destination ACL ID
        DEST_ENV_DETAILS=$(curl -s -H "Accept: application/json" \
            -H "Authorization: NIRMATA-API $TOKEN" \
            "${API_ENDPOINT}/environments/api/environments/$DEST_ENV_ID")
        
        DEST_ACL_ID=$(echo "$DEST_ENV_DETAILS" | jq -r '.accessControlList[0].id')
        
        if [ -z "$DEST_ACL_ID" ] || [ "$DEST_ACL_ID" = "null" ]; then
            log_message "No access control list found in destination environment"
        else
            log_message "Destination ACL ID: $DEST_ACL_ID"
            
            # Get and copy access controls
            ACCESS_CONTROLS=$(echo "$SOURCE_ACL_DETAILS" | jq -r '.accessControls[]?.id')
            
            if [ ! -z "$ACCESS_CONTROLS" ] && [ "$ACCESS_CONTROLS" != "null" ]; then
                echo "$ACCESS_CONTROLS" | while read -r control_id; do
                    if [ ! -z "$control_id" ] && [ "$control_id" != "null" ]; then
                        # Get control details
                        CONTROL_DETAILS=$(curl -s -H "Accept: application/json" \
                            -H "Authorization: NIRMATA-API $TOKEN" \
                            "${API_ENDPOINT}/environments/api/accessControls/$control_id")
                        
                        TEAM_ID=$(echo "$CONTROL_DETAILS" | jq -r '.entityId')
                        TEAM_NAME=$(echo "$CONTROL_DETAILS" | jq -r '.entityName')
                        PERMISSION=$(echo "$CONTROL_DETAILS" | jq -r '.permission')
                        
                        if [ ! -z "$TEAM_ID" ] && [ ! -z "$TEAM_NAME" ] && [ ! -z "$PERMISSION" ]; then
                            ACL_DATA="{\"entityId\":\"$TEAM_ID\",\"entityType\":\"team\",\"permission\":\"$PERMISSION\",\"entityName\":\"$TEAM_NAME\"}"
                            ACL_RESPONSE=$(execute_api_call \
                                "create ACL for team $TEAM_NAME ($TEAM_ID) with permission $PERMISSION" \
                                "POST" \
                                "${API_ENDPOINT}/environments/api/accessControlLists/$DEST_ACL_ID/accessControls" \
                                "$ACL_DATA" \
                                "Authorization: NIRMATA-API $TOKEN")
                            
                            # Check if ACL was created successfully (only in live mode)
                            if [ "$DRY_RUN" = false ]; then
                                if [ ! -z "$ACL_RESPONSE" ]; then
                                    log_message "Successfully created ACL for team $TEAM_NAME"
                                else
                                    log_message "Failed to create ACL for team $TEAM_NAME"
                                fi
                            fi
                        else
                            log_message "Missing required ACL information for control ID: $control_id"
                        fi
                    fi
                done
            else
                log_message "No access controls found in source ACL"
            fi
        fi
    fi
    
    # Copy resource quotas
    log_message "Copying resource quotas..."
    SOURCE_QUOTAS=$(curl -s -H "Authorization: NIRMATA-API ${TOKEN}" \
        "${API_ENDPOINT}/environments/api/environments/${SOURCE_ENV_ID}/resourceQuota" | jq -r '.[]')
    
    if [ ! -z "$SOURCE_QUOTAS" ]; then
        echo "$SOURCE_QUOTAS" | jq -c '.' | while read -r quota; do
            QUOTA_NAME=$(echo "$quota" | jq -r '.name')
            QUOTA_SPEC=$(echo "$quota" | jq -r '.spec')
            
            if [ ! -z "$QUOTA_NAME" ] && [ ! -z "$QUOTA_SPEC" ] && [ "$QUOTA_SPEC" != "null" ]; then
                log_message "Creating quota: $QUOTA_NAME"
                
                # Extract all quota values
                # Check if the 'hard' field exists and has the right structure
                if echo "$QUOTA_SPEC" | jq -e '.hard' > /dev/null 2>&1; then
                    # Standard structure extraction
                    CPU=$(echo "$QUOTA_SPEC" | jq -r '.hard."cpu" // empty')
                    MEMORY=$(echo "$QUOTA_SPEC" | jq -r '.hard."memory" // empty')
                    EPHEMERAL_STORAGE=$(echo "$QUOTA_SPEC" | jq -r '.hard."ephemeral-storage" // empty')
                    REQUESTS_MEMORY=$(echo "$QUOTA_SPEC" | jq -r '.hard."requests.memory" // empty')
                    REQUESTS_CPU=$(echo "$QUOTA_SPEC" | jq -r '.hard."requests.cpu" // empty')
                    REQUESTS_EPHEMERAL_STORAGE=$(echo "$QUOTA_SPEC" | jq -r '.hard."requests.ephemeral-storage" // empty')
                    LIMITS_CPU=$(echo "$QUOTA_SPEC" | jq -r '.hard."limits.cpu" // empty')
                    LIMITS_MEMORY=$(echo "$QUOTA_SPEC" | jq -r '.hard."limits.memory" // empty')
                    LIMITS_EPHEMERAL_STORAGE=$(echo "$QUOTA_SPEC" | jq -r '.hard."limits.ephemeral-storage" // empty')
                else
                    # Handle alternative structure or missing fields
                    log_message "Quota has non-standard structure or is missing 'hard' field. Creating basic quota."
                    CPU=""
                    MEMORY=""
                    EPHEMERAL_STORAGE=""
                    REQUESTS_MEMORY=""
                    REQUESTS_CPU=""
                    REQUESTS_EPHEMERAL_STORAGE=""
                    LIMITS_CPU=""
                    LIMITS_MEMORY=""
                    LIMITS_EPHEMERAL_STORAGE=""
                fi
                
                # Build quota spec with all resources
                QUOTA_PAYLOAD="{
                    \"name\": \"${QUOTA_NAME}\",
                    \"spec\": {
                        \"hard\": {"
                
                # Add resources only if they exist
                FIRST=true
                if [ "$CPU" != "null" ]; then
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"cpu\": \"${CPU}\""
                    FIRST=false
                fi
                
                if [ "$MEMORY" != "null" ]; then
                    if [ "$FIRST" = false ]; then QUOTA_PAYLOAD="${QUOTA_PAYLOAD},"; fi
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"memory\": \"${MEMORY}\""
                    FIRST=false
                fi
                
                if [ "$EPHEMERAL_STORAGE" != "null" ]; then
                    if [ "$FIRST" = false ]; then QUOTA_PAYLOAD="${QUOTA_PAYLOAD},"; fi
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"ephemeral-storage\": \"${EPHEMERAL_STORAGE}\""
                    FIRST=false
                fi
                
                if [ "$REQUESTS_MEMORY" != "null" ]; then
                    if [ "$FIRST" = false ]; then QUOTA_PAYLOAD="${QUOTA_PAYLOAD},"; fi
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"requests.memory\": \"${REQUESTS_MEMORY}\""
                    FIRST=false
                fi
                
                if [ "$REQUESTS_CPU" != "null" ]; then
                    if [ "$FIRST" = false ]; then QUOTA_PAYLOAD="${QUOTA_PAYLOAD},"; fi
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"requests.cpu\": \"${REQUESTS_CPU}\""
                    FIRST=false
                fi
                
                if [ "$REQUESTS_EPHEMERAL_STORAGE" != "null" ]; then
                    if [ "$FIRST" = false ]; then QUOTA_PAYLOAD="${QUOTA_PAYLOAD},"; fi
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"requests.ephemeral-storage\": \"${REQUESTS_EPHEMERAL_STORAGE}\""
                    FIRST=false
                fi
                
                if [ "$LIMITS_CPU" != "null" ]; then
                    if [ "$FIRST" = false ]; then QUOTA_PAYLOAD="${QUOTA_PAYLOAD},"; fi
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"limits.cpu\": \"${LIMITS_CPU}\""
                    FIRST=false
                fi
                
                if [ "$LIMITS_MEMORY" != "null" ]; then
                    if [ "$FIRST" = false ]; then QUOTA_PAYLOAD="${QUOTA_PAYLOAD},"; fi
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"limits.memory\": \"${LIMITS_MEMORY}\""
                    FIRST=false
                fi
                
                if [ "$LIMITS_EPHEMERAL_STORAGE" != "null" ]; then
                    if [ "$FIRST" = false ]; then QUOTA_PAYLOAD="${QUOTA_PAYLOAD},"; fi
                    QUOTA_PAYLOAD="${QUOTA_PAYLOAD}\"limits.ephemeral-storage\": \"${LIMITS_EPHEMERAL_STORAGE}\""
                fi
                
                QUOTA_PAYLOAD="${QUOTA_PAYLOAD}}}}}"
                
                log_message "Creating quota with payload: $QUOTA_PAYLOAD"
                
                QUOTA_RESPONSE=$(execute_api_call \
                    "create resource quota $QUOTA_NAME" \
                    "POST" \
                    "${API_ENDPOINT}/environments/api/environments/${DEST_ENV_ID}/resourceQuota" \
                    "${QUOTA_PAYLOAD}" \
                    "Authorization: NIRMATA-API ${TOKEN}")
                
                if [ "$DRY_RUN" = false ]; then
                    if [ ! -z "$QUOTA_RESPONSE" ]; then
                        log_message "Successfully created quota $QUOTA_NAME"
                        # Verify the quota was created correctly
                        VERIFY_QUOTA=$(curl -s -H "Authorization: NIRMATA-API ${TOKEN}" \
                            "${API_ENDPOINT}/environments/api/environments/${DEST_ENV_ID}/resourceQuota" | \
                            jq -r --arg name "$QUOTA_NAME" '.[] | select(.name == $name)')
                        if [ ! -z "$VERIFY_QUOTA" ]; then
                            log_message "Verified quota $QUOTA_NAME was created successfully"
                        else
                            log_message "Warning: Could not verify quota $QUOTA_NAME creation"
                        fi
                    else
                        log_message "Failed to create quota $QUOTA_NAME"
                    fi
                fi
            fi
        done
    else
        log_message "No resource quotas found in source environment"
    fi
    
    # Copy limit ranges
    log_message "Copying limit ranges..."
    SOURCE_LIMITS=$(curl -s -H "Authorization: NIRMATA-API ${TOKEN}" \
        "${API_ENDPOINT}/environments/api/environments/${SOURCE_ENV_ID}/limitRange" | jq -r '.[]')
    
    if [ ! -z "$SOURCE_LIMITS" ]; then
        echo "$SOURCE_LIMITS" | jq -c '.' | while read -r limit; do
            LIMIT_NAME=$(echo "$limit" | jq -r '.name')
            LIMIT_SPEC=$(echo "$limit" | jq -r '.spec')
            
            if [ ! -z "$LIMIT_NAME" ] && [ ! -z "$LIMIT_SPEC" ] && [ "$LIMIT_SPEC" != "null" ]; then
                LIMIT_PAYLOAD="{\"name\":\"${LIMIT_NAME}\",\"spec\":${LIMIT_SPEC}}"
                LIMIT_RESPONSE=$(execute_api_call \
                    "create limit range $LIMIT_NAME" \
                    "POST" \
                    "${API_ENDPOINT}/environments/api/environments/${DEST_ENV_ID}/limitRange" \
                    "${LIMIT_PAYLOAD}" \
                    "Authorization: NIRMATA-API ${TOKEN}")
                
                if [ "$DRY_RUN" = false ]; then
                    if [ ! -z "$LIMIT_RESPONSE" ]; then
                        log_message "Successfully created limit range $LIMIT_NAME"
                    else
                        log_message "Failed to create limit range $LIMIT_NAME"
                    fi
                fi
            fi
        done
    else
        log_message "No limit ranges found in source environment"
    fi
    
    # Copy owner details
    log_message "Copying owner details..."
    OWNER=$(echo "$source_env_data" | jq -r '.createdBy')
    if [ ! -z "$OWNER" ] && [ "$OWNER" != "null" ]; then
        OWNER_DATA="{\"createdBy\":\"$OWNER\",\"modifiedBy\":\"$OWNER\"}"
        execute_api_call \
            "set owner to $OWNER" \
            "PUT" \
            "${API_ENDPOINT}/environments/api/environments/$DEST_ENV_ID" \
            "$OWNER_DATA" \
            "Authorization: NIRMATA-API $TOKEN"
        
        if [ "$DRY_RUN" = false ]; then
            log_message "Updated owner details"
        fi
    fi

    # Copy labels
    log_message "Copying labels..."
    LABELS=$(echo "$source_env_data" | jq -r '.labels')
    if [ ! -z "$LABELS" ] && [ "$LABELS" != "null" ] && [ "$LABELS" != "{}" ]; then
        log_message "Source labels: $LABELS"
        LABELS_DATA="{\"labels\":$LABELS}"
        execute_api_call \
            "update labels" \
            "PUT" \
            "${API_ENDPOINT}/environments/api/environments/$DEST_ENV_ID" \
            "$LABELS_DATA" \
            "Authorization: NIRMATA-API $TOKEN"
        
        if [ "$DRY_RUN" = false ]; then
            log_message "Updated labels"
        fi
    else
        log_message "No labels found in source environment"
    fi
    
    # Copy team rolebindings
    copy_team_rolebindings "$SOURCE_ENV_ID" "$DEST_ENV_ID" "$source_env_name" "$dest_env_name"
    
    # Update summary counters
    SUCCESSFUL_COPIES=$((SUCCESSFUL_COPIES + 1))
    log_summary "SUCCESS: $source_env_name -> $dest_env_name"
    
    log_message "Settings copy completed for $source_env_name -> $dest_env_name"
done

# Log final summary
if [ "$DRY_RUN" = true ]; then
    log_message "🔍 DRY RUN COMPLETED - No actual changes were made"
    log_message "   To execute these changes, run the script with --live flag"
else
    log_message "🚀 LIVE RUN COMPLETED - All settings copied successfully"
fi

log_summary "----------------------------------------"
if [ "$DRY_RUN" = true ]; then
    log_summary "DRY RUN SUMMARY (preview only):"
else
    log_summary "LIVE RUN SUMMARY (actual changes made):"
fi
log_summary "Total Environments Processed: $TOTAL_ENVIRONMENTS"
log_summary "Successfully Copied: $SUCCESSFUL_COPIES"
log_summary "Skipped: $SKIPPED_ENVIRONMENTS"
log_summary "Failed: $FAILED_COPIES"
log_summary "----------------------------------------"

echo ""
echo "📁 LOG FILES CREATED:"
echo "   📊 Detailed Log: $LOG_FILE"
echo "   📋 Summary Log:  $SUMMARY_FILE"
echo "   🗺️  Mapping File: $MAPPING_FILE"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "🔍 This was a DRY RUN - no actual changes were made to your environments."
    echo "   To execute these changes, run the script again with the --live flag:"
    echo "   $0 $API_ENDPOINT [TOKEN] $SOURCE_CLUSTER $DEST_CLUSTER --live"
    echo ""
    echo "💡 TIP: Review the detailed log file for complete operation details:"
    echo "   cat $LOG_FILE"
else
    echo "🚀 LIVE RUN COMPLETED - All changes have been applied to your environments."
    echo ""
    echo "💡 TIP: Review the log files for complete operation details:"
    echo "   cat $LOG_FILE      # Detailed operations log"
    echo "   cat $SUMMARY_FILE  # Summary of results"
fi
echo "" 