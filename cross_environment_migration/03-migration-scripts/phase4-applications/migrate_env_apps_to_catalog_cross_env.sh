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

LOG_FILE="logs/migration_${SOURCE_CLUSTER_NAME}_to_${DEST_CLUSTER_NAME}_$(date +%Y%m%d_%H%M%S).log"

# Function to log messages to both console and file
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
    local dest_response=$(curl -s -w "%{http_code}" -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/catalog/api/catalogs")
    local dest_http_code=${dest_response: -3}
    
    if [ "$dest_http_code" != "200" ]; then
        log_message "ERROR: Destination environment authentication failed. HTTP code: $dest_http_code"
        return 1
    fi
    log_message "Destination environment authentication successful"
    
    return 0
}

# Function to check if application exists in destination catalog
check_application_exists() {
    local app_name=$1
    local response=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/catalog/api/applications?fields=id,name" | jq -r ".[] | select(.name == \"$app_name\")")
    echo "$response"
}

# Function to get git credential reference from source application
get_git_credential_reference() {
    local git_upstream_id=$1
    local response=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/gitupstreams/$git_upstream_id")
    
    # First try to get credential ID from the credential field
    local cred_id=$(echo "$response" | jq -r '.credential.id // empty')
    
    if [ -z "$cred_id" ] || [ "$cred_id" = "null" ]; then
        # Try getting from gitCredential field if credential didn't work
        cred_id=$(echo "$response" | jq -r '.gitCredential.id // empty')
    fi
    
    if [ ! -z "$cred_id" ] && [ "$cred_id" != "null" ]; then
        # Get the credential name using the ID
        local cred_details=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/gitcredentials/$cred_id")
        local cred_name=$(echo "$cred_details" | jq -r '.name // empty')
        if [ ! -z "$cred_name" ] && [ "$cred_name" != "null" ]; then
            echo "$cred_name"
        fi
    fi
}

# Function to get destination environment git credential name
get_destination_git_credential() {
    local cred_name=$1
    local response=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/environments/api/gitcredentials")
    if [ ! -z "$response" ]; then
        # First try to find credential with the same name
        local matching_cred=$(echo "$response" | jq -r ".[] | select(.name == \"$cred_name\") | .name")
        if [ ! -z "$matching_cred" ] && [ "$matching_cred" != "null" ]; then
            echo "$matching_cred"
            return 0
        fi
        
        # If not found, get the first available credential
        echo "$response" | jq -r '.[0].name // empty'
    fi
}

# Function to get consistent catalog app name
get_catalog_app_name() {
    local app_name=$1
    local source_env=$2
    local cluster_name=$3
    
    # Extract base name without any cluster suffixes or timestamps
    local base_name=$(echo "$app_name" | sed -E 's/-[0-9]+(-[0-9]+)?$//' | sed "s/-${SOURCE_CLUSTER_NAME}$//")
    
    # Create consistent catalog app name with cluster identifier
    echo "app-${base_name}-${cluster_name}"
}

# Function to migrate application
migrate_application() {
    local APP_ID=$1
    local CATALOG_ID=$2
    local SOURCE_ENV=$3
    
    # Get application details from source
    local APP_DETAILS=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/applications/$APP_ID")
    local APP_NAME=$(echo "$APP_DETAILS" | jq -r '.name')
    
    # Get consistent catalog app name with cluster identifier
    local CATALOG_APP_NAME=$(get_catalog_app_name "$APP_NAME" "$SOURCE_ENV" "$SOURCE_CLUSTER_NAME")
    
    # Check if catalog app already exists in destination
    local EXISTING_APP=$(check_application_exists "$CATALOG_APP_NAME")
    if [ ! -z "$EXISTING_APP" ]; then
        log_message "Catalog application $CATALOG_APP_NAME already exists in destination, skipping creation"
        return 0
    fi
    
    # Get Git upstream details
    local GIT_UPSTREAM=$(echo "$APP_DETAILS" | jq -r '.gitUpstream[0]')
    if [ -z "$GIT_UPSTREAM" ] || [ "$GIT_UPSTREAM" = "null" ]; then
        log_message "No Git upstream found for application $APP_NAME"
        return 1
    fi
    
    # Get Git credential reference from source
    local SOURCE_GIT_CRED_NAME=$(get_git_credential_reference "$(echo "$GIT_UPSTREAM" | jq -r '.id')")
    if [ -z "$SOURCE_GIT_CRED_NAME" ]; then
        log_message "No Git credential found for application $APP_NAME"
        return 1
    fi
    
    # Get corresponding git credential in destination
    local DEST_GIT_CRED_NAME=$(get_destination_git_credential "$SOURCE_GIT_CRED_NAME")
    if [ -z "$DEST_GIT_CRED_NAME" ]; then
        log_message "No matching Git credential found in destination for application $APP_NAME"
        return 1
    fi
    
    log_message "Using Git credential: $DEST_GIT_CRED_NAME in destination for application $APP_NAME"
    
    # Create catalog application with cluster-specific configuration in destination
    local CATALOG_APP_PAYLOAD=$(cat <<EOF
{
    "name": "$CATALOG_APP_NAME",
    "description": "Migrated from environment $SOURCE_ENV in cluster $SOURCE_CLUSTER_NAME",
    "catalog": "$CATALOG_ID",
    "gitUpstream": $GIT_UPSTREAM,
    "gitCredential": "$DEST_GIT_CRED_NAME",
    "service": "Catalog",
    "modelIndex": "Application",
    "metadata": {
        "sourceCluster": "$SOURCE_CLUSTER_NAME",
        "sourceEnvironment": "$SOURCE_ENV",
        "originalAppName": "$APP_NAME",
        "sourceEndpoint": "$SOURCE_API_ENDPOINT"
    }
}
EOF
)
    
    local CATALOG_APP_RESPONSE=$(curl -s -X POST -H "Authorization: NIRMATA-API $DEST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$CATALOG_APP_PAYLOAD" \
        "$DEST_API_ENDPOINT/catalog/api/applications")
    
    if [ $? -eq 0 ] && [ ! -z "$CATALOG_APP_RESPONSE" ]; then
        log_message "Successfully created catalog application: $CATALOG_APP_NAME in destination"
        return 0
    else
        log_message "Failed to create catalog application: $CATALOG_APP_NAME in destination"
        log_message "Response: $CATALOG_APP_RESPONSE"
        return 1
    fi
}

# Function to process a single environment
process_environment() {
    local SOURCE_ENV=$1
    local processed_count=0
    local success_count=0
    local skip_count=0
    local fail_count=0
    local has_git_apps=false

    log_message "Processing environment: $SOURCE_ENV"

    # First check if there are any Git-based applications
    log_message "Checking for Git-based applications in environment $SOURCE_ENV..."
    APPS_RESPONSE=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/applications?fields=id,name,gitUpstream,yamlData")
    
    if [ "$(echo "$APPS_RESPONSE" | jq 'length')" -eq 0 ]; then
        log_message "No applications found in environment $SOURCE_ENV"
        return
    fi

    # Check if any application has Git upstream
    while read -r app; do
        if [ -n "$app" ]; then
            APP_ID=$(echo "$app" | jq -r '.id')
            GIT_UPSTREAM_COUNT=$(echo "$app" | jq '.gitUpstream | length')
            
            if [ "$GIT_UPSTREAM_COUNT" -gt 0 ]; then
                has_git_apps=true
                break
            fi
        fi
    done < <(echo "$APPS_RESPONSE" | jq -c '.[]')

    # Only proceed with catalog creation if there are Git-based applications
    if [ "$has_git_apps" = true ]; then
        # Get catalog name from environment name, removing any unnecessary suffixes
        CATALOG_NAME=$(echo "$SOURCE_ENV" | sed 's/-[0-9].*$//')
        
        # Check if catalog already exists in destination
        log_message "Checking if catalog $CATALOG_NAME already exists in destination..."
        CATALOG_RESPONSE=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/catalog/api/catalogs?fields=id,name")
        CATALOG_ID=$(echo "$CATALOG_RESPONSE" | jq -r ".[] | select(.name == \"$CATALOG_NAME\") | .id")

        if [ -z "$CATALOG_ID" ]; then
            # Create new catalog in destination
            log_message "Creating new catalog: $CATALOG_NAME in destination"
            CATALOG_PAYLOAD=$(cat <<EOF
{
    "name": "$CATALOG_NAME",
    "description": "Migrated catalog from cluster $SOURCE_CLUSTER_NAME",
    "service": "Catalog",
    "modelIndex": "Catalog"
}
EOF
)
            CATALOG_CREATE_RESPONSE=$(curl -s -X POST -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$CATALOG_PAYLOAD" \
                "$DEST_API_ENDPOINT/catalog/api/catalogs")
            
            CATALOG_ID=$(echo "$CATALOG_CREATE_RESPONSE" | jq -r '.id')
            
            if [ -z "$CATALOG_ID" ] || [ "$CATALOG_ID" = "null" ]; then
                log_message "Failed to create catalog $CATALOG_NAME in destination"
                return 1
            fi
            
            log_message "Successfully created catalog: $CATALOG_NAME with ID: $CATALOG_ID in destination"
        else
            log_message "Using existing catalog: $CATALOG_NAME with ID: $CATALOG_ID in destination"
        fi

        # Process each application with Git upstream
        while read -r app; do
            if [ -n "$app" ]; then
                APP_ID=$(echo "$app" | jq -r '.id')
                APP_NAME=$(echo "$app" | jq -r '.name')
                GIT_UPSTREAM_COUNT=$(echo "$app" | jq '.gitUpstream | length')
                
                if [ "$GIT_UPSTREAM_COUNT" -gt 0 ]; then
                    log_message "Processing Git-based application: $APP_NAME"
                    
                    if migrate_application "$APP_ID" "$CATALOG_ID" "$SOURCE_ENV"; then
                        success_count=$((success_count + 1))
                        log_message "Successfully migrated: $APP_NAME"
                    else
                        fail_count=$((fail_count + 1))
                        log_message "Failed to migrate: $APP_NAME"
                    fi
                    processed_count=$((processed_count + 1))
                else
                    log_message "Skipping non-Git application: $APP_NAME"
                    skip_count=$((skip_count + 1))
                fi
            fi
        done < <(echo "$APPS_RESPONSE" | jq -c '.[]')
        
        log_message "Environment $SOURCE_ENV processing complete:"
        log_message "  - Processed: $processed_count Git applications"
        log_message "  - Successful: $success_count"
        log_message "  - Failed: $fail_count"
        log_message "  - Skipped: $skip_count non-Git applications"
    else
        log_message "No Git-based applications found in environment $SOURCE_ENV"
    fi
}

# Main execution starts here
log_message "Starting cross-environment migration process"
log_message "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER_NAME)"
log_message "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER_NAME)"

# Check authentication for both environments
if ! check_auth; then
    log_message "Authentication failed. Exiting."
    exit 1
fi

# Get cluster ID for source cluster name
log_message "Getting cluster ID for source cluster: $SOURCE_CLUSTER_NAME"
SOURCE_CLUSTER_ID=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/clusters" | jq -r ".[] | select(.name == \"$SOURCE_CLUSTER_NAME\") | .id")

if [ -z "$SOURCE_CLUSTER_ID" ]; then
    log_message "No cluster found with name '$SOURCE_CLUSTER_NAME' in source environment"
    exit 1
fi

log_message "Found source cluster ID: $SOURCE_CLUSTER_ID"

# Get all environments for the source cluster using cluster ID
log_message "Finding environments for source cluster: $SOURCE_CLUSTER_NAME"
ENVIRONMENTS=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/environments" | jq -r ".[] | select(.cluster[0].id == \"$SOURCE_CLUSTER_ID\") | .name")

if [ -z "$ENVIRONMENTS" ]; then
    log_message "No environments found for source cluster '$SOURCE_CLUSTER_NAME'"
    exit 1
fi

log_message "Found environments in source cluster:"
echo "$ENVIRONMENTS" | while read -r env; do
    log_message "  - $env"
done

# Process each environment
echo "$ENVIRONMENTS" | while read -r SOURCE_ENV; do
    if [ -n "$SOURCE_ENV" ]; then
        process_environment "$SOURCE_ENV"
    fi
done

log_message "Cross-environment migration process completed"
log_message "Check the log file for detailed results: $LOG_FILE" 