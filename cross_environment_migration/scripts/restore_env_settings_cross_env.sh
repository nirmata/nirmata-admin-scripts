#!/bin/bash

# Check if required parameters are provided
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <source_api_endpoint> <source_token> <source_cluster> <dest_api_endpoint> <dest_token> <dest_cluster>"
    echo ""
    echo "Example:"
    echo "$0 https://pe420.nirmata.co 'SOURCE_TOKEN' '123-app-migration' https://staging.nirmata.co 'DEST_TOKEN' 'conformance-132'"
    exit 1
fi

SOURCE_API_ENDPOINT=$1
SOURCE_TOKEN=$2
SOURCE_CLUSTER=$3
DEST_API_ENDPOINT=$4
DEST_TOKEN=$5
DEST_CLUSTER=$6

# Create logs directory if it doesn't exist
LOG_DIR="logs"
mkdir -p "$LOG_DIR"

# Create log file with timestamp
LOG_FILE="${LOG_DIR}/env_restore_cross_env_$(date '+%Y%m%d_%H%M%S').log"
SUMMARY_FILE="${LOG_DIR}/env_restore_summary_cross_env_$(date '+%Y%m%d_%H%M%S').log"

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

# Initialize summary counters
TOTAL_ENVIRONMENTS=0
SUCCESSFUL_COPIES=0
SKIPPED_ENVIRONMENTS=0
FAILED_COPIES=0

log_message "Starting cross-environment settings restoration"
log_message "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER)"
log_message "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER)"

log_summary "Cross-Environment Settings Restoration Summary"
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

# Get source clusters
SOURCE_CLUSTERS_RESPONSE=$(curl -s -H "Accept: application/json" \
    -H "Authorization: NIRMATA-API ${SOURCE_TOKEN}" \
    "${SOURCE_API_ENDPOINT}/environments/api/clusters")

# Check if unauthorized
if echo "$SOURCE_CLUSTERS_RESPONSE" | grep -q "Not authorized"; then
    log_message "Error: Not authorized for source environment. Please check your token."
    log_message "Response: $SOURCE_CLUSTERS_RESPONSE"
    exit 1
fi

# Check if response is valid JSON
if ! echo "$SOURCE_CLUSTERS_RESPONSE" | jq '.' >/dev/null 2>&1; then
    log_message "Error: Invalid JSON response from source clusters API"
    log_message "Response: $SOURCE_CLUSTERS_RESPONSE"
    exit 1
fi

# Get destination clusters
DEST_CLUSTERS_RESPONSE=$(curl -s -H "Accept: application/json" \
    -H "Authorization: NIRMATA-API ${DEST_TOKEN}" \
    "${DEST_API_ENDPOINT}/environments/api/clusters")

# Check if unauthorized
if echo "$DEST_CLUSTERS_RESPONSE" | grep -q "Not authorized"; then
    log_message "Error: Not authorized for destination environment. Please check your token."
    log_message "Response: $DEST_CLUSTERS_RESPONSE"
    exit 1
fi

# Check if response is valid JSON
if ! echo "$DEST_CLUSTERS_RESPONSE" | jq '.' >/dev/null 2>&1; then
    log_message "Error: Invalid JSON response from destination clusters API"
    log_message "Response: $DEST_CLUSTERS_RESPONSE"
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

# Get source environments
SOURCE_ENVIRONMENTS_RESPONSE=$(curl -s -H "Accept: application/json" \
    -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
    "${SOURCE_API_ENDPOINT}/environments/api/environments")

# Check if response is valid JSON
if ! echo "$SOURCE_ENVIRONMENTS_RESPONSE" | jq '.' >/dev/null 2>&1; then
    log_message "Error: Invalid JSON response from source environments API"
    log_message "Response: $SOURCE_ENVIRONMENTS_RESPONSE"
    exit 1
fi

# Get destination environments
DEST_ENVIRONMENTS_RESPONSE=$(curl -s -H "Accept: application/json" \
    -H "Authorization: NIRMATA-API $DEST_TOKEN" \
    "${DEST_API_ENDPOINT}/environments/api/environments")

# Check if response is valid JSON
if ! echo "$DEST_ENVIRONMENTS_RESPONSE" | jq '.' >/dev/null 2>&1; then
    log_message "Error: Invalid JSON response from destination environments API"
    log_message "Response: $DEST_ENVIRONMENTS_RESPONSE"
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
    
    curl -s -X POST -H "Authorization: NIRMATA-API $DEST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$DEST_API_ENDPOINT/environments/api/environments/$env_id/teamrolebindings"
    
    log_message "Created team rolebinding in destination for team $team_name"
}

# Function to find corresponding destination environment
find_dest_environment() {
    local source_env_name=$1
    
    # Try to find environment with same name in destination
    local dest_env=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg name "$source_env_name" '.[] | select(.cluster[].id == $cluster and .name == $name)')
    
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        echo "$dest_env"
        return 0
    fi
    
    # If exact match not found, try pattern matching (remove cluster suffix and match)
    local base_name=$(echo "$source_env_name" | sed "s/-${SOURCE_CLUSTER}$//" | sed "s/-[0-9]*$//")
    local dest_env_pattern=$(echo "$DEST_ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$DEST_CLUSTER_ID" --arg pattern "$base_name" '.[] | select(.cluster[].id == $cluster and (.name | contains($pattern)))')
    
    if [ ! -z "$dest_env_pattern" ] && [ "$dest_env_pattern" != "null" ]; then
        echo "$dest_env_pattern"
        return 0
    fi
    
    return 1
}

# Function to copy team rolebindings from source to destination
copy_team_rolebindings() {
    local source_env_id=$1
    local dest_env_id=$2
    local source_env_name=$3
    local dest_env_name=$4
    
    log_message "Copying team rolebindings from source $source_env_name to destination $dest_env_name"
    
    # Get source ACL ID
    SOURCE_ACL_ID=$(curl -s -H "Accept: application/json" \
        -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
        "${SOURCE_API_ENDPOINT}/environments/api/environments/$source_env_id" | jq -r '.accessControlList[0].id')

    if [ ! -z "$SOURCE_ACL_ID" ] && [ "$SOURCE_ACL_ID" != "null" ]; then
        # Get source ACL details
        SOURCE_ACL_DETAILS=$(curl -s -H "Accept: application/json" \
            -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
            "${SOURCE_API_ENDPOINT}/environments/api/accessControlLists/$SOURCE_ACL_ID")
        
        # Get access control IDs
        ACCESS_CONTROL_IDS=$(echo "$SOURCE_ACL_DETAILS" | jq -r '.accessControls[].id')
        
        # Process each access control
        for control_id in $ACCESS_CONTROL_IDS; do
            # Get access control details from source
            CONTROL_DETAILS=$(curl -s -H "Accept: application/json" \
                -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
                "${SOURCE_API_ENDPOINT}/environments/api/accessControls/$control_id")
            
            ENTITY_ID=$(echo "$CONTROL_DETAILS" | jq -r '.entityId')
            ENTITY_TYPE=$(echo "$CONTROL_DETAILS" | jq -r '.entityType')
            PERMISSION=$(echo "$CONTROL_DETAILS" | jq -r '.permission')
            ENTITY_NAME=$(echo "$CONTROL_DETAILS" | jq -r '.entityName')
            
            if [ "$ENTITY_TYPE" = "Team" ]; then
                log_message "Processing team: $ENTITY_NAME with permission: $PERMISSION"
                
                # Find corresponding team in destination
                DEST_TEAM_RESPONSE=$(curl -s -H "Accept: application/json" \
                    -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                    "${DEST_API_ENDPOINT}/users/api/teams")
                
                DEST_TEAM_ID=$(echo "$DEST_TEAM_RESPONSE" | jq -r --arg name "$ENTITY_NAME" '.[] | select(.name == $name) | .id')
                
                if [ ! -z "$DEST_TEAM_ID" ] && [ "$DEST_TEAM_ID" != "null" ]; then
                    # Find corresponding role in destination
                    DEST_ROLES_RESPONSE=$(curl -s -H "Accept: application/json" \
                        -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                        "${DEST_API_ENDPOINT}/users/api/roles")
                    
                    # Map permission to role (assuming standard roles)
                    local role_name=""
                    case "$PERMISSION" in
                        "read")
                            role_name="environment.view"
                            ;;
                        "write")
                            role_name="environment.admin"
                            ;;
                        "admin")
                            role_name="environment.admin"
                            ;;
                        *)
                            role_name="environment.view"
                            ;;
                    esac
                    
                    DEST_ROLE_ID=$(echo "$DEST_ROLES_RESPONSE" | jq -r --arg name "$role_name" '.[] | select(.name == $name) | .id')
                    
                    if [ ! -z "$DEST_ROLE_ID" ] && [ "$DEST_ROLE_ID" != "null" ]; then
                        create_dest_team_rolebinding "$dest_env_id" "$DEST_TEAM_ID" "$DEST_ROLE_ID" "$ENTITY_NAME" "$PERMISSION"
                        log_message "Successfully created team rolebinding for $ENTITY_NAME in destination"
                    else
                        log_message "Warning: Could not find role $role_name in destination"
                    fi
                else
                    log_message "Warning: Team $ENTITY_NAME not found in destination"
                fi
            fi
        done
    else
        log_message "No access control list found for source environment $source_env_name"
    fi
}

# Function to copy environment settings
copy_environment_settings() {
    local source_env_name=$1
    local source_env_data=$2
    
    TOTAL_ENVIRONMENTS=$((TOTAL_ENVIRONMENTS + 1))
    
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
    
    log_message "Found destination environment: $dest_env_name (ID: $dest_env_id)"
    
    # Copy team rolebindings
    if copy_team_rolebindings "$source_env_id" "$dest_env_id" "$source_env_name" "$dest_env_name"; then
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

while read -r source_env_data; do
    if [ -n "$source_env_data" ]; then
        source_env_name=$(echo "$source_env_data" | jq -r '.name')
        copy_environment_settings "$source_env_name" "$source_env_data"
    fi
done < <(echo "$SOURCE_ENVIRONMENTS" | jq -c '.')

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

if [ $FAILED_COPIES -gt 0 ]; then
    log_message "WARNING: Some environment settings failed to copy. Check the logs for details."
    exit 1
else
    log_message "All environment settings copied successfully!"
    exit 0
fi 