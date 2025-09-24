#!/bin/bash

# Check if all required arguments are provided
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <source_api_endpoint> <source_token> <source_cluster_name> <dest_api_endpoint> <dest_token> <dest_cluster_name>"
    echo ""
    echo "Example:"
    echo "$0 https://source.nirmata.co 'SOURCE_TOKEN' 'source-cluster' https://destination.nirmata.co 'DEST_TOKEN' 'dest-cluster'"
    exit 1
fi

SOURCE_API_ENDPOINT=$1
SOURCE_TOKEN=$2
SOURCE_CLUSTER_NAME=$3
DEST_API_ENDPOINT=$4
DEST_TOKEN=$5
DEST_CLUSTER_NAME=$6

# Create logs directory if it doesn't exist
mkdir -p logs

# Generate log file name with timestamp
LOG_FILE="logs/catalog_reference_update_cross_env_$(date +%Y%m%d_%H%M%S).log"

# Function to log messages
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

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
    local dest_response=$(curl -s -w "%{http_code}" -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/catalog/api/applications")
    local dest_http_code=${dest_response: -3}
    
    if [ "$dest_http_code" != "200" ]; then
        log_message "ERROR: Destination environment authentication failed. HTTP code: $dest_http_code"
        return 1
    fi
    log_message "Destination environment authentication successful"
    
    return 0
}

# Function to find catalog application in destination
find_catalog_application() {
    local app_name=$1
    local base_name=$2
    local cluster_name=$3
    
    log_message "Looking for catalog application in destination for: $app_name (base name: $base_name, cluster: $cluster_name)"
    
    # Try different patterns to find the catalog application in destination
    local patterns=(
        "app-${app_name}-${SOURCE_CLUSTER_NAME}"
        "app-${app_name}-${cluster_name}"
        "app-${app_name}"
        "${app_name}"
        "app-${base_name}-${SOURCE_CLUSTER_NAME}"
        "app-${base_name}-${cluster_name}"
        "app-${base_name}"
        "${base_name}"
    )
    
    for pattern in "${patterns[@]}"; do
        log_message "Trying pattern in destination: $pattern"
        local response=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/catalog/api/applications?fields=id,name" | jq -r ".[] | select(.name == \"$pattern\")")
        
        if [ ! -z "$response" ] && [ "$response" != "null" ]; then
            local catalog_app_id=$(echo "$response" | jq -r '.id')
            log_message "Found catalog application in destination with ID: $catalog_app_id"
            echo "$catalog_app_id"
            return 0
        fi
    done
    
    log_message "No catalog application found in destination for: $app_name"
    return 1
}

# Function to make API calls with retries to destination
make_dest_api_call() {
    local endpoint=$1
    local method=${2:-GET}
    local data=$3
    local max_retries=3
    local retry_count=0
    local wait_time=5

    while [ $retry_count -lt $max_retries ]; do
        if [ -n "$data" ]; then
            local response=$(curl -s -w "%{http_code}" -X "$method" \
                -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$data" \
                "$DEST_API_ENDPOINT$endpoint")
        else
            local response=$(curl -s -w "%{http_code}" -X "$method" \
                -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                "$DEST_API_ENDPOINT$endpoint")
        fi

        local http_code=${response: -3}
        local body=${response%???}

        case $http_code in
            200|201|202|204)
                echo "$body"
                return 0
                ;;
            401)
                log_message "ERROR: Authentication failed for destination. Please check your token."
                return 1
                ;;
            403)
                log_message "ERROR: Permission denied for destination. Please check your access rights."
                return 1
                ;;
            404)
                log_message "ERROR: Resource not found in destination: $endpoint"
                return 1
                ;;
            429)
                log_message "WARNING: Rate limit exceeded on destination. Waiting before retry..."
                sleep $wait_time
                wait_time=$((wait_time * 2))
                ;;
            500|502|503|504)
                log_message "WARNING: Server error on destination ($http_code). Retrying in $wait_time seconds..."
                sleep $wait_time
                wait_time=$((wait_time * 2))
                ;;
            *)
                log_message "ERROR: Unexpected HTTP code from destination: $http_code"
                log_message "Response: $body"
                return 1
                ;;
        esac

        retry_count=$((retry_count + 1))
    done

    log_message "ERROR: Maximum retries reached for destination endpoint: $endpoint"
    return 1
}

# Function to get destination cluster ID
get_destination_cluster_id() {
    log_message "Getting destination cluster ID for: $DEST_CLUSTER_NAME"
    local dest_cluster_id=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/environments/api/clusters" | jq -r ".[] | select(.name == \"$DEST_CLUSTER_NAME\") | .id")
    
    if [ -z "$dest_cluster_id" ]; then
        log_message "No cluster found with name '$DEST_CLUSTER_NAME' in destination environment"
        return 1
    fi
    
    log_message "Found destination cluster ID: $dest_cluster_id"
    echo "$dest_cluster_id"
    return 0
}

# Function to get destination environments
get_destination_environments() {
    local dest_cluster_id=$1
    log_message "Finding environments for destination cluster: $DEST_CLUSTER_NAME"
    
    local environments=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/environments/api/environments" | jq -r ".[] | select(.cluster[0].id == \"$dest_cluster_id\") | .name")
    
    if [ -z "$environments" ]; then
        log_message "No environments found for destination cluster '$DEST_CLUSTER_NAME'"
        return 1
    fi
    
    echo "$environments"
    return 0
}

# Function to update catalog reference in destination environment with enhanced error handling
update_catalog_reference_in_destination() {
    local dest_env_name=$1
    local app_name=$2
    local catalog_app_id=$3
    local max_retries=3
    local retry_count=0
    local wait_time=5

    log_message "Finding application '$app_name' in destination environment '$dest_env_name'"
    
    # Get destination application ID
    local dest_apps_response=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/environments/api/applications?fields=id,name")
    local dest_app_id=$(echo "$dest_apps_response" | jq -r ".[] | select(.name == \"$app_name\") | .id")
    
    if [ -z "$dest_app_id" ]; then
        log_message "Application '$app_name' not found in destination environment '$dest_env_name'"
        return 1
    fi
    
    log_message "Found destination application ID: $dest_app_id"
    log_message "Updating catalog reference for application $dest_app_id to catalog application $catalog_app_id"

    while [ $retry_count -lt $max_retries ]; do
        # Update catalog reference in destination
        local update_data="{\"catalogApplicationId\": \"$catalog_app_id\"}"
        local update_response=$(make_dest_api_call "/environments/api/applications/$dest_app_id" "PUT" "$update_data")
        if [ $? -ne 0 ]; then
            log_message "ERROR: Failed to update catalog reference for $app_name in destination"
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_message "Retrying in $wait_time seconds... (Attempt $((retry_count + 1)) of $max_retries)"
                sleep $wait_time
                wait_time=$((wait_time * 2))
                continue
            fi
            return 1
        fi

        log_message "Successfully updated catalog reference for $app_name in destination"
        return 0
    done

    log_message "ERROR: Maximum retries reached for updating catalog reference for $app_name in destination"
    return 1
}

# Function to process application with error handling
process_application() {
    local app_id=$1
    local app_name=$2
    local cluster_name=$3
    local base_name=$4

    log_message "Processing application: $app_name (ID: $app_id)"

    # Get catalog application ID from destination
    local catalog_app_id=$(find_catalog_application "$app_name" "$base_name" "$cluster_name")
    if [ -z "$catalog_app_id" ]; then
        log_message "No catalog application found in destination for: $app_name"
        return 0
    fi

    # Get destination environments and update catalog references
    local dest_cluster_id=$(get_destination_cluster_id)
    if [ -z "$dest_cluster_id" ]; then
        log_message "ERROR: Could not get destination cluster ID"
        return 1
    fi
    
    local dest_environments=$(get_destination_environments "$dest_cluster_id")
    if [ -z "$dest_environments" ]; then
        log_message "ERROR: Could not get destination environments"
        return 1
    fi
    
    # Update catalog reference in each destination environment
    echo "$dest_environments" | while read -r dest_env; do
        if [ -n "$dest_env" ]; then
            if ! update_catalog_reference_in_destination "$dest_env" "$app_name" "$catalog_app_id"; then
                log_message "ERROR: Failed to update catalog reference for $app_name in destination environment $dest_env after multiple retries"
                return 1
            fi
        fi
    done

    return 0
}

# Function to process environment
process_environment() {
    local source_env=$1
    local total_apps=0
    local successful_updates=0
    local failed_updates=0
    local skipped_apps=0

    log_message "Processing source environment: $source_env"

    # Get applications from source environment
    local apps_response=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/applications?fields=id,name,gitUpstream")
    
    if [ "$(echo "$apps_response" | jq 'length')" -eq 0 ]; then
        log_message "No applications found in source environment $source_env"
        return
    fi

    # Process each application that has Git upstream
    while read -r app; do
        if [ -n "$app" ]; then
            local app_id=$(echo "$app" | jq -r '.id')
            local app_name=$(echo "$app" | jq -r '.name')
            local git_upstream_count=$(echo "$app" | jq '.gitUpstream | length')
            
            total_apps=$((total_apps + 1))
            
            if [ "$git_upstream_count" -gt 0 ]; then
                log_message "Processing Git-based application: $app_name"
                
                # Extract base name for pattern matching
                local base_name=$(echo "$app_name" | sed -E 's/-[0-9]+(-[0-9]+)?$//' | sed "s/-${SOURCE_CLUSTER_NAME}$//")
                
                if process_application "$app_id" "$app_name" "$SOURCE_CLUSTER_NAME" "$base_name"; then
                    successful_updates=$((successful_updates + 1))
                    log_message "Successfully processed: $app_name"
                else
                    failed_updates=$((failed_updates + 1))
                    log_message "Failed to process: $app_name"
                fi
            else
                log_message "Skipping non-Git application: $app_name"
                skipped_apps=$((skipped_apps + 1))
            fi
        fi
    done < <(echo "$apps_response" | jq -c '.[]')

    log_message "Environment $source_env processing complete:"
    log_message "  - Total applications: $total_apps"
    log_message "  - Successful updates: $successful_updates"
    log_message "  - Failed updates: $failed_updates"
    log_message "  - Skipped non-Git apps: $skipped_apps"
}

# Main execution starts here
log_message "Starting cross-environment catalog reference update"
log_message "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER_NAME)"
log_message "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER_NAME)"

# Check authentication for both environments
if ! check_auth; then
    log_message "Authentication failed. Exiting."
    exit 1
fi

# Get source cluster ID
log_message "Getting cluster ID for source cluster: $SOURCE_CLUSTER_NAME"
SOURCE_CLUSTER_ID=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/clusters" | jq -r ".[] | select(.name == \"$SOURCE_CLUSTER_NAME\") | .id")

if [ -z "$SOURCE_CLUSTER_ID" ]; then
    log_message "No cluster found with name '$SOURCE_CLUSTER_NAME' in source environment"
    exit 1
fi

log_message "Found source cluster ID: $SOURCE_CLUSTER_ID"

# Get all environments for the source cluster
log_message "Finding environments for source cluster: $SOURCE_CLUSTER_NAME"
SOURCE_ENVIRONMENTS=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/environments" | jq -r ".[] | select(.cluster[0].id == \"$SOURCE_CLUSTER_ID\") | .name")

if [ -z "$SOURCE_ENVIRONMENTS" ]; then
    log_message "No environments found for source cluster '$SOURCE_CLUSTER_NAME'"
    exit 1
fi

log_message "Found environments in source cluster:"
echo "$SOURCE_ENVIRONMENTS" | while read -r env; do
    log_message "  - $env"
done

# Initialize counters
TOTAL_ENVIRONMENTS=0
SUCCESSFUL_ENVIRONMENTS=0
FAILED_ENVIRONMENTS=0

# Process each source environment
echo "$SOURCE_ENVIRONMENTS" | while read -r source_env; do
    if [ -n "$source_env" ]; then
        TOTAL_ENVIRONMENTS=$((TOTAL_ENVIRONMENTS + 1))
        
        if process_environment "$source_env"; then
            SUCCESSFUL_ENVIRONMENTS=$((SUCCESSFUL_ENVIRONMENTS + 1))
        else
            FAILED_ENVIRONMENTS=$((FAILED_ENVIRONMENTS + 1))
        fi
    fi
done

log_message "Cross-environment catalog reference update completed"
log_message "Check the log file for detailed results: $LOG_FILE" 