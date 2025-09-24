#!/bin/bash

# Check if all required arguments are provided
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <api_endpoint> <token> <source_cluster_name> <destination_cluster_name> [options]"
    echo ""
    echo "This script links environment applications to their catalog counterparts."
    echo "It should be run AFTER the enhanced migration script has created catalog applications."
    echo "🔧 FIXED: Uses the correct API approach for catalog reference updates"
    echo "🔍 ENHANCED: Comprehensive pattern matching for robust catalog app detection"
    echo ""
    echo "Options:"
    echo "  --dry-run        Show what would be done without making changes"
    echo "  --interactive    Review and confirm each mapping before applying"
    echo "  --auto           Run automatically without prompts (default)"
    echo ""
    echo "Enhanced Logic:"
    echo "- Smart pattern matching: removes cluster names, versions, timestamps, prefixes"
    echo "- Multiple matching strategies: exact, fuzzy, case-insensitive, prefix/suffix"
    echo "- Interactive mode allows manual catalog app selection if auto-detection fails"
    echo "- When no catalog app is found, interactive mode shows all available catalog apps"
    echo "- Full y/n/list/skip options for complete control over catalog mappings"
    echo "- Uses the proper API method for persistent catalog references"
    echo ""
    echo "Examples:"
    echo "  # Dry run to see what would happen"
    echo "  $0 https://staging.nirmata.co 'TOKEN' 'source-cluster' 'dest-cluster' --dry-run"
    echo ""
    echo "  # Interactive mode to review each mapping"
    echo "  $0 https://staging.nirmata.co 'TOKEN' 'source-cluster' 'dest-cluster' --interactive"
    echo ""
    echo "  # Auto mode (default)"
    echo "  $0 https://staging.nirmata.co 'TOKEN' 'source-cluster' 'dest-cluster' --auto"
    exit 1
fi

API_ENDPOINT=$1
TOKEN=$2
SOURCE_CLUSTER_NAME=$3
DESTINATION_CLUSTER_NAME=$4

# Parse mode flags
DRY_RUN=false
INTERACTIVE=false
AUTO=true

# Process remaining arguments
shift 4
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            AUTO=false
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            AUTO=false
            shift
            ;;
        --auto)
            AUTO=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set mode descriptions
if [ "$DRY_RUN" = true ]; then
    MODE_DESC="🔍 DRY RUN - No changes will be made"
elif [ "$INTERACTIVE" = true ]; then
    MODE_DESC="🎯 INTERACTIVE - Review each mapping"
else
    MODE_DESC="🚀 AUTO - Apply all mappings automatically"
fi

# Create logs directory if it doesn't exist
mkdir -p logs

# Generate log file name with timestamp and mode
LOG_FILE="logs/catalog_reference_fixed_${SOURCE_CLUSTER_NAME}_to_${DESTINATION_CLUSTER_NAME}_$(date +%Y%m%d_%H%M%S).log"
if [ "$DRY_RUN" = true ]; then
    LOG_FILE="logs/catalog_reference_fixed_${SOURCE_CLUSTER_NAME}_to_${DESTINATION_CLUSTER_NAME}_dryrun_$(date +%Y%m%d_%H%M%S).log"
fi

# Function to log messages
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$MODE_DESC] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

# Function to validate JSON response (from restore_env_settings.sh)
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

# Function to safely extract JSON field (from restore_env_settings.sh)
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

# Function to make safe API call with error handling (from restore_env_settings.sh)
make_safe_api_call() {
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

# Function to check authentication
check_auth() {
    log_message "Checking authentication..."
    local response=$(curl -s -w "%{http_code}" -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/catalog/api/applications")
    local http_code=${response: -3}
    
    if [ "$http_code" = "200" ]; then
        log_message "Authentication successful"
        return 0
    else
        log_message "ERROR: Authentication failed. HTTP code: $http_code"
        return 1
    fi
}



# Function to find catalog application using comprehensive pattern matching
find_catalog_application() {
    local app_name=$1
    
    log_message "Looking for catalog application matching: $app_name" >&2
    
    # Validate input
    if [ -z "$app_name" ]; then
        log_message "ERROR: Empty application name provided" >&2
        return 1
    fi
    
    # Get all catalog applications once for efficiency using safe API call
    local ALL_CATALOG_APPS
    if ! ALL_CATALOG_APPS=$(make_safe_api_call "GET" "$API_ENDPOINT/catalog/api/applications?fields=id,name" "$TOKEN" "" "catalog-applications"); then
        log_message "ERROR: Failed to get catalog applications list" >&2
        return 1
    fi
    
    # Strategy 1: Exact match
    local catalog_response=$(echo "$ALL_CATALOG_APPS" | jq -r ".[] | select(.name == \"$app_name\")" 2>/dev/null || echo "")
    if [ ! -z "$catalog_response" ] && [ "$catalog_response" != "null" ]; then
        log_message "Found exact match: $app_name" >&2
        echo "$catalog_response"
        return 0
    fi
    
    # Strategy 2: Extract base name from various patterns
    local base_name=""
    local source_cluster_lower=$(echo "$SOURCE_CLUSTER_NAME" | tr '[:upper:]' '[:lower:]')
    local dest_cluster_lower=$(echo "$DESTINATION_CLUSTER_NAME" | tr '[:upper:]' '[:lower:]')
    
    # Pattern 1: Remove destination cluster suffix (app-name-cluster)
    if [[ "$app_name" == *"-$DESTINATION_CLUSTER_NAME" ]]; then
        base_name=$(echo "$app_name" | sed "s/-$DESTINATION_CLUSTER_NAME$//")
        log_message "Detected destination cluster suffix pattern. Extracted base name: $base_name" >&2
    # Pattern 2: Remove source cluster suffix (app-name-source-cluster)
    elif [[ "$app_name" == *"-$SOURCE_CLUSTER_NAME" ]]; then
        base_name=$(echo "$app_name" | sed "s/-$SOURCE_CLUSTER_NAME$//")
        log_message "Detected source cluster suffix pattern. Extracted base name: $base_name" >&2
    # Pattern 3: Remove cluster prefix (cluster-app-name)
    elif [[ "$app_name" == "$DESTINATION_CLUSTER_NAME-"* ]]; then
        base_name=$(echo "$app_name" | sed "s/^$DESTINATION_CLUSTER_NAME-//")
        log_message "Detected destination cluster prefix pattern. Extracted base name: $base_name" >&2
    elif [[ "$app_name" == "$SOURCE_CLUSTER_NAME-"* ]]; then
        base_name=$(echo "$app_name" | sed "s/^$SOURCE_CLUSTER_NAME-//")
        log_message "Detected source cluster prefix pattern. Extracted base name: $base_name" >&2
    # Pattern 4: Case-insensitive cluster matching
    elif [[ "$(echo "$app_name" | tr '[:upper:]' '[:lower:]')" == *"-$dest_cluster_lower" ]]; then
        base_name=$(echo "$(echo "$app_name" | tr '[:upper:]' '[:lower:]')" | sed "s/-$dest_cluster_lower$//")
        log_message "Detected case-insensitive destination cluster suffix. Extracted base name: $base_name" >&2
    elif [[ "$(echo "$app_name" | tr '[:upper:]' '[:lower:]')" == *"-$source_cluster_lower" ]]; then
        base_name=$(echo "$(echo "$app_name" | tr '[:upper:]' '[:lower:]')" | sed "s/-$source_cluster_lower$//")
        log_message "Detected case-insensitive source cluster suffix. Extracted base name: $base_name" >&2
    # Pattern 5: Remove timestamp suffix (app-name-20250710123456)
    elif [[ "$app_name" =~ -[0-9]{14}$ ]]; then
        base_name=$(echo "$app_name" | sed -E 's/-[0-9]{14}$//')
        log_message "Detected timestamp suffix pattern. Extracted base name: $base_name" >&2
    # Pattern 6: Remove version suffix (app-name-v1, app-name-2)
    elif [[ "$app_name" =~ -v[0-9]+$ ]] || [[ "$app_name" =~ -[0-9]+$ ]]; then
        base_name=$(echo "$app_name" | sed -E 's/-v[0-9]+$//' | sed -E 's/-[0-9]+$//')
        log_message "Detected version suffix pattern. Extracted base name: $base_name" >&2
    # Pattern 7: Remove common prefixes (app-, application-)
    elif [[ "$app_name" == "app-"* ]]; then
        base_name=$(echo "$app_name" | sed 's/^app-//')
        log_message "Detected 'app-' prefix pattern. Extracted base name: $base_name" >&2
    elif [[ "$app_name" == "application-"* ]]; then
        base_name=$(echo "$app_name" | sed 's/^application-//')
        log_message "Detected 'application-' prefix pattern. Extracted base name: $base_name" >&2
    else
        base_name="$app_name"
        log_message "No pattern detected. Using full name as base name: $base_name" >&2
    fi
    
    # Strategy 3: Try to find catalog application using extracted base name
    
    # Pattern A: Exact base name match
    catalog_response=$(echo "$ALL_CATALOG_APPS" | jq -r ".[] | select(.name == \"$base_name\")" 2>/dev/null || echo "")
    if [ ! -z "$catalog_response" ] && [ "$catalog_response" != "null" ]; then
        log_message "Found base name match: $base_name" >&2
        echo "$catalog_response"
        return 0
    fi
    
    # Pattern B: Base name with version (base-v1, base-v2, etc.)
    catalog_response=$(echo "$ALL_CATALOG_APPS" | jq -r ".[] | select(.name | test(\"^${base_name}-v[0-9]+$\"))" 2>/dev/null || echo "")
    if [ ! -z "$catalog_response" ] && [ "$catalog_response" != "null" ]; then
        local matched_name=$(echo "$catalog_response" | jq -r '.name' 2>/dev/null || echo "$base_name")
        log_message "Found versioned base name match: $matched_name" >&2
        echo "$catalog_response"
        return 0
    fi
    
    # Pattern C: Base name with numeric suffix (base-1, base-2, etc.)
    catalog_response=$(echo "$ALL_CATALOG_APPS" | jq -r ".[] | select(.name | test(\"^${base_name}-[0-9]+$\"))")
    if [ ! -z "$catalog_response" ] && [ "$catalog_response" != "null" ]; then
        local matched_name=$(echo "$catalog_response" | jq -r '.name')
        log_message "Found numeric suffix match: $matched_name" >&2
        echo "$catalog_response"
        return 0
    fi
    
    # Pattern D: Case-insensitive base name
    catalog_response=$(echo "$ALL_CATALOG_APPS" | jq -r ".[] | select(.name | ascii_downcase == \"$(echo "$base_name" | tr '[:upper:]' '[:lower:]')\")")
    if [ ! -z "$catalog_response" ] && [ "$catalog_response" != "null" ]; then
        local matched_name=$(echo "$catalog_response" | jq -r '.name')
        log_message "Found case-insensitive match: $matched_name" >&2
        echo "$catalog_response"
        return 0
    fi
    
    # Pattern E: Base name with any suffix containing base name
    catalog_response=$(echo "$ALL_CATALOG_APPS" | jq -r ".[] | select(.name | startswith(\"${base_name}-\"))")
    if [ ! -z "$catalog_response" ] && [ "$catalog_response" != "null" ]; then
        local matched_name=$(echo "$catalog_response" | jq -r '.name')
        log_message "Found prefix match: $matched_name" >&2
        echo "$catalog_response"
        return 0
    fi
    
    # Strategy 4: Fuzzy matching - catalog apps containing the base name
    catalog_response=$(echo "$ALL_CATALOG_APPS" | jq -r ".[] | select(.name | contains(\"$base_name\"))")
    if [ ! -z "$catalog_response" ] && [ "$catalog_response" != "null" ]; then
        local matched_name=$(echo "$catalog_response" | jq -r '.name')
        log_message "Found fuzzy match containing '$base_name': $matched_name" >&2
        echo "$catalog_response"
        return 0
    fi
    
    # Strategy 5: Last resort - base name contained in catalog app names
    catalog_response=$(echo "$ALL_CATALOG_APPS" | jq -r ".[] | select(\"$base_name\" | contains(.name))")
    if [ ! -z "$catalog_response" ] && [ "$catalog_response" != "null" ]; then
        local matched_name=$(echo "$catalog_response" | jq -r '.name')
        log_message "Found reverse fuzzy match where '$base_name' contains: $matched_name" >&2
        echo "$catalog_response"
        return 0
    fi
    
    # Strategy 6: Debug information
    log_message "No catalog application found for: $app_name" >&2
    log_message "Extracted base name: $base_name" >&2
    log_message "Available catalog applications:" >&2
    
    local catalog_list
    catalog_list=$(echo "$ALL_CATALOG_APPS" | jq -r '.[].name' 2>/dev/null | head -10)
    
    if [ $? -eq 0 ] && [ ! -z "$catalog_list" ]; then
        echo "$catalog_list" | while read -r catalog_name; do
            log_message "  - $catalog_name" >&2
        done
    else
        log_message "ERROR: Failed to parse catalog applications list" >&2
    fi
    
    return 1
}

# Function to interactively handle missing catalog application
interactive_handle_missing_catalog() {
    local app_name="$1"
    local env_name="$2"
    
    echo ""
    echo "⚠️  NO CATALOG APPLICATION FOUND"
    echo "=================================="
    echo "Environment Application: $app_name"
    echo "Environment: $env_name"
    echo "No automatic catalog match found using comprehensive pattern matching."
    echo ""
    echo "Available catalog applications:"
    local catalog_apps
    if catalog_apps=$(make_safe_api_call "GET" "$API_ENDPOINT/catalog/api/applications" "$TOKEN" "" "catalog-apps-list"); then
        echo "$catalog_apps" | jq -r '.[] | "  - " + .name + " (ID: " + .id + ")"' 2>/dev/null | sort || echo "  - (Failed to parse catalog applications)"
    else
        echo "  - (Failed to retrieve catalog applications)"
    fi
    echo ""
    
    while true; do
        echo -n "Enter catalog application name for '$app_name' (or 'skip' to skip): "
        read -r custom_catalog_name </dev/tty
        
        # Handle empty input
        if [ -z "$custom_catalog_name" ]; then
            echo "❌ Empty input detected. Please enter a catalog application name or 'skip'."
            continue
        fi
        
        if [ "$custom_catalog_name" = "skip" ]; then
            echo "⏭️  Skipping application: $app_name"
            return 1
        fi
        
        # Validate the custom catalog application exists
        local catalog_apps_response
        local custom_catalog_response=""
        if catalog_apps_response=$(make_safe_api_call "GET" "$API_ENDPOINT/catalog/api/applications" "$TOKEN" "" "catalog-apps-validate"); then
            custom_catalog_response=$(echo "$catalog_apps_response" | jq -r ".[] | select(.name == \"$custom_catalog_name\")" 2>/dev/null || echo "")
        fi
        
        if [ ! -z "$custom_catalog_response" ] && [ "$custom_catalog_response" != "null" ]; then
            local custom_catalog_id=$(echo "$custom_catalog_response" | jq -r '.id' 2>/dev/null)
            echo "✅ Manual mapping confirmed: $app_name → $custom_catalog_name"
            echo "$custom_catalog_name|$custom_catalog_id"
            return 0
        else
            echo "❌ Error: Catalog application '$custom_catalog_name' not found"
            echo "Please choose from the available catalog applications listed above."
            echo ""
        fi
    done
}

# Function to interactively confirm catalog application mapping
interactive_confirm_catalog_mapping() {
    local app_name="$1"
    local suggested_catalog_name="$2"
    local suggested_catalog_id="$3"
    local env_name="$4"
    
    echo ""
    echo "🔍 CATALOG APPLICATION MAPPING CONFIRMATION"
    echo "=============================================="
    echo "Environment Application: $app_name"
    echo "Environment: $env_name"
    echo "Suggested Catalog App: $suggested_catalog_name"
    echo ""
    
    while true; do
        echo -n "Link '$app_name' to catalog application '$suggested_catalog_name'? (y/n/list/skip): "
        read -r response </dev/tty
        
        # Handle empty input
        if [ -z "$response" ]; then
            echo "❌ Empty input detected. Please enter 'y', 'n', 'list', or 'skip'."
            continue
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]|"y"|"Y"|"yes"|"YES")
                echo "✅ Confirmed: $app_name → $suggested_catalog_name"
                echo "$suggested_catalog_name|$suggested_catalog_id"
                return 0
                ;;
            [Ss][Kk][Ii][Pp]|"skip"|"SKIP")
                echo "⏭️  Skipping application: $app_name"
                return 1
                ;;
            [Nn]|[Nn][Oo]|"n"|"N"|"no"|"NO")
                echo ""
                echo "❌ Mapping rejected. Please specify the correct catalog application."
                echo ""
                echo "Available catalog applications:"
                local catalog_apps
                if catalog_apps=$(make_safe_api_call "GET" "$API_ENDPOINT/catalog/api/applications" "$TOKEN" "" "catalog-apps-list"); then
                    echo "$catalog_apps" | jq -r '.[] | "  - " + .name + " (ID: " + .id + ")"' 2>/dev/null | sort || echo "  - (Failed to parse catalog applications)"
                else
                    echo "  - (Failed to retrieve catalog applications)"
                fi
                echo ""
                
                while true; do
                    echo -n "Enter the correct catalog application name (or 'skip' to skip this mapping): "
                    read -r custom_catalog_name </dev/tty
                    
                    # Handle empty input
                    if [ -z "$custom_catalog_name" ]; then
                        echo "❌ Empty input detected. Please enter a catalog application name or 'skip'."
                        continue
                    fi
                    
                    if [ "$custom_catalog_name" = "skip" ]; then
                        echo "⏭️  Skipping application: $app_name"
                        return 1
                    fi
                    
                    # Validate the custom catalog application exists
                    local catalog_apps_response
                    local custom_catalog_response=""
                    if catalog_apps_response=$(make_safe_api_call "GET" "$API_ENDPOINT/catalog/api/applications" "$TOKEN" "" "catalog-apps-validate"); then
                        custom_catalog_response=$(echo "$catalog_apps_response" | jq -r ".[] | select(.name == \"$custom_catalog_name\")" 2>/dev/null || echo "")
                    fi
                    
                    if [ ! -z "$custom_catalog_response" ] && [ "$custom_catalog_response" != "null" ]; then
                        local custom_catalog_id=$(echo "$custom_catalog_response" | jq -r '.id' 2>/dev/null)
                        echo "✅ Custom mapping confirmed: $app_name → $custom_catalog_name"
                        echo "$custom_catalog_name|$custom_catalog_id"
                        return 0
                    else
                        echo "❌ Error: Catalog application '$custom_catalog_name' not found"
                        echo "Please choose from the available catalog applications listed above."
                        echo ""
                    fi
                done
                ;;
            [Ll][Ii][Ss][Tt]|"list"|"LIST")
                echo ""
                echo "📋 Available catalog applications:"
                local catalog_apps
                if catalog_apps=$(make_safe_api_call "GET" "$API_ENDPOINT/catalog/api/applications" "$TOKEN" "" "catalog-apps-list"); then
                    echo "$catalog_apps" | jq -r '.[] | "  - " + .name + " (ID: " + .id + ")"' 2>/dev/null | sort || echo "  - (Failed to parse catalog applications)"
                else
                    echo "  - (Failed to retrieve catalog applications)"
                fi
                echo ""
                echo "💡 You can now:"
                echo "  - Type 'y' to confirm the suggested mapping: $suggested_catalog_name"
                echo "  - Type 'n' to manually specify a different catalog app"
                echo "  - Type 'skip' to skip this application"
                echo ""
                # Continue the loop to ask again
                ;;
            *)
                echo "Invalid response: '$response'. Please answer 'y' for yes, 'n' for no, 'list' to see available catalog apps, or 'skip' to skip."
                ;;
        esac
    done
}

# Function to make API call with proper error handling
make_catalog_reference_api_call() {
    local app_id=$1
    local catalog_app_id=$2
    local catalog_app_name=$3
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        # Use the correct API approach - just set catalogApplication field
        local update_data=$(cat <<UPDATE_DATA
{
    "catalogApplication": {
        "id": "$catalog_app_id",
        "name": "$catalog_app_name",
        "service": "Catalog",
        "modelIndex": "Application"
    }
}
UPDATE_DATA
)
        
        local response=$(curl -s -w "%{http_code}" \
            -X PUT \
            -H "Authorization: NIRMATA-API $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$update_data" \
            "$API_ENDPOINT/environments/api/applications/$app_id")
        
        local http_code=${response: -3}
        
        if [ "$http_code" = "200" ]; then
            return 0
        elif [ "$http_code" = "429" ]; then
            # Rate limited, wait and retry
            local wait_time=$((5 * (retry_count + 1)))
            log_message "Rate limited, waiting $wait_time seconds before retry..."
            sleep $wait_time
        else
            log_message "ERROR: API call failed with HTTP code: $http_code"
            return 1
        fi
        
        retry_count=$((retry_count + 1))
    done
    
    log_message "ERROR: Maximum retries reached for app $app_id"
    return 1
}

# Function to show mapping preview
show_mapping_preview() {
    local app_name=$1
    local app_id=$2
    local catalog_app_name=$3
    local catalog_app_id=$4
    local env_name=$5
    
    echo ""
    echo "========================================"
    echo "📋 MAPPING PREVIEW"
    echo "========================================"
    echo "Environment App:"
    echo "  Name: $app_name"
    echo "  ID: $app_id"
    echo "  Environment: $env_name"
    echo "  Cluster: $DESTINATION_CLUSTER_NAME"
    echo ""
    echo "Will be linked to Catalog App:"
    echo "  Name: $catalog_app_name"
    echo "  ID: $catalog_app_id"
    echo "  🔧 Fixed API Method"
    echo "========================================"
}

# Function to show real-time mapping info for auto mode
show_realtime_mapping() {
    local app_name=$1
    local app_id=$2
    local catalog_app_name=$3
    local catalog_app_id=$4
    local env_name=$5
    local action=$6  # "LINKING" or "UPDATING"
    
    echo ""
    echo "🔗 [$action] Destination App: '$app_name' → Catalog App: '$catalog_app_name'"
    echo "   📍 Environment: $env_name"
    echo "   📍 Destination Cluster: $DESTINATION_CLUSTER_NAME"
    echo "   🔧 Fixed API Method"
    log_message "$action catalog reference: $app_name ($app_id) → $catalog_app_name ($catalog_app_id) in $env_name"
}

# Function to get user confirmation
get_user_confirmation() {
    local prompt="$1"
    local default_answer="${2:-y}"
    
    while true; do
        read -p "$prompt [y/N/q]: " answer
        case ${answer:-$default_answer} in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            [Qq]* ) 
                log_message "User chose to quit"
                exit 0
                ;;
            * ) echo "Please answer y (yes), n (no), or q (quit).";;
        esac
    done
}

# Function to verify catalog reference was set correctly
verify_catalog_reference() {
    local app_id=$1
    local expected_catalog_app_id=$2
    
    local app_details
    local actual_catalog_app_id=""
    if app_details=$(make_safe_api_call "GET" "$API_ENDPOINT/environments/api/applications/$app_id" "$TOKEN" "" "app-verification"); then
        actual_catalog_app_id=$(safe_json_extract "$app_details" '.additionalProperties.catalogApplication.id' "")
    fi
    
    if [ "$actual_catalog_app_id" = "$expected_catalog_app_id" ]; then
        return 0
    else
        return 1
    fi
}

# Main script execution
echo ""
echo "🔧 FIXED Catalog Reference Update (Proper API Method)"
echo "====================================================="
echo "This script uses the correct API approach for catalog"
echo "reference updates that persist properly."
echo ""

log_message "Starting FIXED catalog reference update process"
log_message "Mode: $MODE_DESC"

# Create temporary file for mapping data
MAPPINGS_FILE=$(mktemp)
trap "rm -f $MAPPINGS_FILE" EXIT

# Check authentication first
if ! check_auth; then
    log_message "ERROR: Authentication check failed. Exiting."
    exit 1
fi

# Get destination cluster ID
log_message "Getting cluster ID for destination cluster: $DESTINATION_CLUSTER_NAME"
clusters_response=$(make_safe_api_call "GET" "$API_ENDPOINT/environments/api/clusters" "$TOKEN" "" "clusters")
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to get clusters list"
    exit 1
fi
DESTINATION_CLUSTER_ID=$(safe_json_extract "$clusters_response" ".[] | select(.name == \"$DESTINATION_CLUSTER_NAME\") | .id" "")

if [ -z "$DESTINATION_CLUSTER_ID" ] || [ "$DESTINATION_CLUSTER_ID" = "null" ]; then
    log_message "ERROR: No cluster found with name '$DESTINATION_CLUSTER_NAME'"
    exit 1
fi

log_message "Found destination cluster ID: $DESTINATION_CLUSTER_ID"

# Get environments from the destination cluster
log_message "Getting environments from destination cluster: $DESTINATION_CLUSTER_NAME..."
all_environments=$(make_safe_api_call "GET" "$API_ENDPOINT/environments/api/environments" "$TOKEN" "" "environments")
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to get environments list"
    exit 1
fi
environments=$(echo "$all_environments" | jq "[.[] | select(.cluster[0].id == \"$DESTINATION_CLUSTER_ID\")]" 2>/dev/null || echo "[]")

environment_count=$(echo "$environments" | jq 'length')
log_message "Found $environment_count environments in destination cluster '$DESTINATION_CLUSTER_NAME'"

if [ "$environment_count" -eq 0 ]; then
    log_message "No environments found in destination cluster '$DESTINATION_CLUSTER_NAME'. Exiting."
    exit 1
fi

# Scan for potential mappings using enhanced pattern matching
log_message "🔧 Scanning for catalog mappings using ENHANCED pattern matching and FIXED API method..."

# Process each environment
env_counter=0
total_envs=$(echo "$environments" | jq 'length')
while read -r env; do
    env_counter=$((env_counter + 1))
    env_id=$(echo "$env" | jq -r '.id')
    env_name=$(echo "$env" | jq -r '.name')
    
    echo ""
    echo "🔍 [$env_counter/$total_envs] Processing environment: $env_name"
    log_message "Scanning environment: $env_name (ID: $env_id)"
    
    # Get applications in the environment using safe API call
    if ! applications=$(make_safe_api_call "GET" "$API_ENDPOINT/environments/api/environments/$env_id/applications" "$TOKEN" "" "environment-applications"); then
        log_message "  ⚠️  Failed to get applications for environment: $env_name"
        continue
    fi
    
    # Check if applications array is empty
    if [ "$(echo "$applications" | jq 'length')" -eq 0 ]; then
        log_message "  ℹ️  No applications found in environment: $env_name"
        continue
    fi
    
    # Check each application
    app_counter=0
    total_apps=$(echo "$applications" | jq 'length' 2>/dev/null || echo "0")
    echo "   📱 Found $total_apps applications in this environment"
    
    while read -r app; do
        if [ -n "$app" ] && [ "$app" != "null" ]; then
            app_counter=$((app_counter + 1))
            app_id=$(echo "$app" | jq -r '.id' 2>/dev/null || echo "")
            app_name=$(echo "$app" | jq -r '.name' 2>/dev/null || echo "")
            
            # Skip if we can't get basic app info
            if [ -z "$app_id" ] || [ -z "$app_name" ] || [ "$app_id" = "null" ] || [ "$app_name" = "null" ]; then
                continue
            fi
            
            echo "      [$app_counter/$total_apps] 🔧 Processing app: $app_name"
            
            # Get app details to check existing catalog reference
            app_details=""
            existing_catalog_ref=""
            if app_details=$(make_safe_api_call "GET" "$API_ENDPOINT/environments/api/applications/$app_id" "$TOKEN" "" "app-details"); then
                existing_catalog_ref=$(safe_json_extract "$app_details" '.additionalProperties.catalogApplication.id' "")
            fi
            
            # Find catalog application using comprehensive pattern matching
            if catalog_response=$(find_catalog_application "$app_name"); then
                catalog_app_id=$(echo "$catalog_response" | jq -r '.id')
                catalog_app_name=$(echo "$catalog_response" | jq -r '.name')
                
                # For interactive mode, confirm the mapping first
                if [ "$INTERACTIVE" = true ]; then
                    if confirmed_mapping=$(interactive_confirm_catalog_mapping "$app_name" "$catalog_app_name" "$catalog_app_id" "$env_name"); then
                        # Parse the confirmed mapping
                        catalog_app_name=$(echo "$confirmed_mapping" | cut -d'|' -f1)
                        catalog_app_id=$(echo "$confirmed_mapping" | cut -d'|' -f2)
                    else
                        # User skipped this mapping
                        log_message "  ⏭️  Skipped mapping for $app_name (user choice)"
                        continue
                    fi
                fi
                
                # Determine action needed
                if [ ! -z "$existing_catalog_ref" ] && [ "$existing_catalog_ref" != "null" ]; then
                    if [ "$existing_catalog_ref" = "$catalog_app_id" ]; then
                        log_message "  ✅ $app_name already correctly linked to $catalog_app_name"
                        continue
                    else
                        # Wrong reference - needs update
                        echo "$app_name|$app_id|$catalog_app_name|$catalog_app_id|$env_name|UPDATE" >> "$MAPPINGS_FILE"
                        log_message "  🔄 Found wrong reference for $app_name → will fix to link to $catalog_app_name"
                    fi
                else
                    # No reference - needs new link
                    echo "$app_name|$app_id|$catalog_app_name|$catalog_app_id|$env_name|LINK" >> "$MAPPINGS_FILE"
                    log_message "  🔗 Found new mapping: $app_name → $catalog_app_name"
                fi
            else
                # Handle case when no catalog app is found
                if [ "$INTERACTIVE" = true ]; then
                    # Interactive mode - allow user to specify catalog app manually
                    if [ ! -z "$existing_catalog_ref" ] && [ "$existing_catalog_ref" != "null" ]; then
                        log_message "  ⚠️  $app_name has catalog reference but no matching catalog app found using enhanced pattern matching"
                        echo ""
                        echo "⚠️  EXISTING CATALOG REFERENCE FOUND"
                        echo "Application '$app_name' has an existing catalog reference but no matching catalog app found."
                        echo "You can specify a different catalog app or skip this application."
                        
                        if confirmed_mapping=$(interactive_handle_missing_catalog "$app_name" "$env_name"); then
                            # Parse the manual mapping
                            catalog_app_name=$(echo "$confirmed_mapping" | cut -d'|' -f1)
                            catalog_app_id=$(echo "$confirmed_mapping" | cut -d'|' -f2)
                            
                            # Wrong reference - needs update
                            echo "$app_name|$app_id|$catalog_app_name|$catalog_app_id|$env_name|UPDATE" >> "$MAPPINGS_FILE"
                            log_message "  🔄 Manual mapping for existing reference: $app_name → $catalog_app_name"
                        else
                            log_message "  ⏭️  Skipped mapping for $app_name (user choice)"
                        fi
                    else
                        log_message "  ℹ️  No catalog found for: $app_name (tried comprehensive pattern matching)"
                        echo ""
                        echo "🔍 APPLICATION: $app_name (Environment: $env_name)"
                        echo "No automatic catalog match found."
                        echo ""
                        echo "Available catalog applications:"
                        
                        # Get and display all available catalog applications dynamically
                        if catalog_list=$(make_safe_api_call "GET" "$API_ENDPOINT/catalog/api/applications" "$TOKEN" "" "catalog-list"); then
                            echo "$catalog_list" | jq -r '.[] | "  - " + .name' 2>/dev/null | sort || echo "  - (Failed to parse catalog applications)"
                        else
                            echo "  - (Failed to retrieve catalog applications)"
                        fi
                        
                        echo ""
                        echo -n "Enter catalog application name for '$app_name' (or 'skip' to skip): "
                        
                        # Add timeout to prevent hanging
                        if read -t 300 -r user_choice </dev/tty; then
                            echo ""  # Add newline after input
                        else
                            echo ""
                            echo "⏰ Input timeout (5 minutes). Skipping $app_name"
                            user_choice="skip"
                        fi
                        
                        if [ "$user_choice" = "skip" ] || [ -z "$user_choice" ]; then
                            log_message "  ⏭️  Skipped mapping for $app_name (user choice)"
                        else
                            # Validate catalog exists
                            if catalog_apps=$(make_safe_api_call "GET" "$API_ENDPOINT/catalog/api/applications" "$TOKEN" "" "catalog-validate"); then
                                catalog_match=$(echo "$catalog_apps" | jq -r ".[] | select(.name == \"$user_choice\")" 2>/dev/null || echo "")
                                if [ ! -z "$catalog_match" ] && [ "$catalog_match" != "null" ]; then
                                    catalog_app_id=$(echo "$catalog_match" | jq -r '.id' 2>/dev/null)
                                    echo "$app_name|$app_id|$user_choice|$catalog_app_id|$env_name|LINK" >> "$MAPPINGS_FILE"
                                    log_message "  🔗 Manual mapping: $app_name → $user_choice"
                                    echo "✅ Mapping confirmed: $app_name → $user_choice"
                                else
                                    echo "❌ Catalog '$user_choice' not found. Skipping $app_name"
                                    log_message "  ⏭️  Invalid catalog choice for $app_name: $user_choice"
                                fi
                            else
                                echo "❌ Failed to validate catalog. Skipping $app_name"
                                log_message "  ⏭️  Failed to validate catalog for $app_name"
                            fi
                        fi
                    fi
                else
                    # Non-interactive mode - just log the issue
                    if [ ! -z "$existing_catalog_ref" ] && [ "$existing_catalog_ref" != "null" ]; then
                        log_message "  ⚠️  $app_name has catalog reference but no matching catalog app found using enhanced pattern matching"
                    else
                        log_message "  ℹ️  No catalog found for: $app_name (tried comprehensive pattern matching)"
                    fi
                fi
            fi
        fi
    done < <(echo "$applications" | jq -c '.[]')
    
done < <(echo "$environments" | jq -c '.[]')

# Process mappings if found
if [ -s "$MAPPINGS_FILE" ]; then
    echo ""
    echo "========================================"
    echo "📊 MAPPING SUMMARY (Fixed API Method)"
    echo "========================================"
    total_mappings=$(wc -l < "$MAPPINGS_FILE")
    echo "Total mappings found: $total_mappings"
    echo ""
    
    cat "$MAPPINGS_FILE" | while IFS='|' read -r app_name app_id catalog_name catalog_id env_name action; do
        if [ "$action" = "UPDATE" ]; then
            echo "  🔄 $app_name → 📦 $catalog_name ($env_name) [FIXING WRONG REFERENCE]"
        else
            echo "  📱 $app_name → 📦 $catalog_name ($env_name) [NEW LINK]"
        fi
    done
    echo "========================================"
    
    # Get confirmation for overall operation
    if [ "$INTERACTIVE" = true ]; then
        echo ""
        if ! get_user_confirmation "Proceed with applying these mappings?"; then
            log_message "User cancelled the operation"
            exit 0
        fi
    fi
    
    # Apply mappings
    log_message "Processing catalog reference mappings with FIXED API method..."
    
    # Counters for summary
    updated_count=0
    linked_count=0
    failed_count=0
    
    while IFS='|' read -r app_name app_id catalog_app_name catalog_app_id env_name action; do
        if [ "$DRY_RUN" = true ]; then
            if [ "$action" = "UPDATE" ]; then
                log_message "DRY RUN: Would fix wrong catalog reference for $app_name → $catalog_app_name"
            else
                log_message "DRY RUN: Would link $app_name to catalog application $catalog_app_name"
            fi
            show_mapping_preview "$app_name" "$app_id" "$catalog_app_name" "$catalog_app_id" "$env_name"
        else
            if [ "$INTERACTIVE" = true ]; then
                show_mapping_preview "$app_name" "$app_id" "$catalog_app_name" "$catalog_app_id" "$env_name"
                if ! get_user_confirmation "Apply this specific mapping?"; then
                    log_message "User skipped mapping for $app_name"
                    continue
                fi
            fi
            
            # Show real-time mapping info in auto mode
            if [ "$AUTO" = true ]; then
                if [ "$action" = "UPDATE" ]; then
                    show_realtime_mapping "$app_name" "$app_id" "$catalog_app_name" "$catalog_app_id" "$env_name" "UPDATING"
                else
                    show_realtime_mapping "$app_name" "$app_id" "$catalog_app_name" "$catalog_app_id" "$env_name" "LINKING"
                fi
            fi
            
            # Make the API call using the fixed method
            if make_catalog_reference_api_call "$app_id" "$catalog_app_id" "$catalog_app_name"; then
                # Verify the reference was set correctly
                if verify_catalog_reference "$app_id" "$catalog_app_id"; then
                    if [ "$action" = "UPDATE" ]; then
                        echo "   ✅ Successfully fixed wrong catalog reference (VERIFIED)"
                        updated_count=$((updated_count + 1))
                    else
                        echo "   ✅ Successfully linked to catalog application (VERIFIED)"
                        linked_count=$((linked_count + 1))
                    fi
                    log_message "Successfully processed and verified catalog reference for $app_name"
                else
                    echo "   ⚠️  API call succeeded but verification failed"
                    failed_count=$((failed_count + 1))
                    log_message "WARNING: API call succeeded but catalog reference verification failed for $app_name"
                fi
            else
                echo "   ❌ Failed to update catalog reference"
                failed_count=$((failed_count + 1))
                log_message "ERROR: Failed to update catalog reference for $app_name"
            fi
        fi
    done < "$MAPPINGS_FILE"
    
    # Show final summary
    echo ""
    echo "========================================"
    echo "🔧 FINAL SUMMARY (Fixed API Method)"
    echo "========================================"
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN COMPLETED - No actual changes made"
        echo "Would have processed: $total_mappings mappings"
    else
        echo "Linked applications: $linked_count"
        echo "Fixed wrong references: $updated_count"
        echo "Failed operations: $failed_count"
        echo "Total processed: $((linked_count + updated_count))"
    fi
    echo "========================================"
    
else
    log_message "No catalog mappings found to apply across all $environment_count environments"
fi

log_message "FIXED catalog reference update process completed"
log_message "Log file: $LOG_FILE"

echo ""
echo "🔧 Fixed API method catalog reference update completed!"
echo "📁 Log file: $LOG_FILE" 