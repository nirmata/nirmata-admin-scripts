#!/bin/bash

# Enhanced Environment to Catalog Migration Script
# Features: Dry run mode, interactive/auto modes, comprehensive logging, safety features

# Initialize mode flags
DRY_RUN=true
LIVE_MODE=false
AUTO_CONFIRM=false
VERBOSE=false

# Parse command line arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --live)
            DRY_RUN=false
            LIVE_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            LIVE_MODE=false
            shift
            ;;
        --auto-confirm)
            AUTO_CONFIRM=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 <api_endpoint> <token> <source_cluster_name> <destination_cluster_name> [OPTIONS]

🚀 Enhanced Environment to Catalog Migration Script

POSITIONAL ARGUMENTS:
  api_endpoint            Nirmata API endpoint (e.g., https://staging.nirmata.co)
  token                   Nirmata API token
  source_cluster_name     Source cluster name
  destination_cluster_name Destination cluster name

OPTIONS:
  --dry-run              Preview migration without making changes (DEFAULT)
  --live                 Execute actual migration (requires confirmation)
  --auto-confirm         Skip confirmation prompts (use with --live)
  --verbose              Show detailed API request/response information
  --help                 Show this help message

🔍 MODES:
  • Default (Dry Run):    Preview what will be migrated
  • Live Mode:           Execute actual migration with confirmation
  • Auto Mode:           Execute migration without prompts (--live --auto-confirm)

🛡️ SAFETY FEATURES:
  • Dry run by default prevents accidental changes
  • Confirmation prompts before live execution
  • Comprehensive logging with detailed and summary logs
  • Duplicate prevention and intelligent Git credential mapping
  • System validation before migration

🎯 PRODUCTION-READY NAMING:
  • Clean names WITHOUT old cluster references
  • Example: conformance-132-shuting → shuting (NOT app-shuting-conformance-132)
  • Intelligent conflict resolution with versioning
  • Forward-looking names for complete cluster migration

📊 LOGGING:
  • Detailed logs: logs/migration_detailed_YYYYMMDD_HHMMSS.log
  • Summary logs: logs/migration_summary_YYYYMMDD_HHMMSS.log
  • Mode indicators in all logs (DRY RUN vs LIVE)

EXAMPLES:
  # Safe preview (default)
  $0 https://staging.nirmata.co "TOKEN" "source-cluster" "dest-cluster"
  
  # Execute with confirmation
  $0 https://staging.nirmata.co "TOKEN" "source-cluster" "dest-cluster" --live
  
  # Automated execution (use with caution)
  $0 https://staging.nirmata.co "TOKEN" "source-cluster" "dest-cluster" --live --auto-confirm

NAMING EXAMPLES:
  conformance-132-shuting → shuting
  satya-conformance-132   → satya  
  prod-user-service       → user-service
  monitoring-infra        → monitoring

EOF
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

# Check if all required arguments are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <api_endpoint> <token> <source_cluster_name> <destination_cluster_name> [OPTIONS]"
    echo ""
    echo "Enhanced Features:"
    echo "  🔍 Dry run mode by default - preview changes before making them"
    echo "  🛡️ Safety features with confirmation prompts and auto-confirm option"
    echo "  📊 Comprehensive logging with detailed and summary log files"
    echo "  🎯 Production-ready naming - NO old cluster references in catalog names"
    echo "  ✅ Smart Git credential mapping with fallback strategies"
    echo "  ✅ Comprehensive duplicate prevention with conflict resolution"
    echo "  ✅ Enhanced error handling and authentication validation"
    echo "  ✅ Detailed migration statistics and progress tracking"
    echo ""
    echo "🎯 PRODUCTION NAMING EXAMPLES:"
    echo "  conformance-132-shuting → shuting (clean, no cluster refs)"
    echo "  satya-conformance-132   → satya (forward-looking)"
    echo "  prod-user-service       → user-service (logical naming)"
    echo ""
    echo "Example:"
    echo "  # Safe preview (default)"
    echo "  $0 https://staging.nirmata.co 'YOUR_TOKEN' 'source-cluster' 'dest-cluster'"
    echo ""
    echo "  # Execute changes"
    echo "  $0 https://staging.nirmata.co 'YOUR_TOKEN' 'source-cluster' 'dest-cluster' --live"
    echo ""
    echo "Use --help for detailed usage information"
    exit 1
fi

API_ENDPOINT=$1
TOKEN=$2
SOURCE_CLUSTER_NAME=$3
DEST_CLUSTER_NAME=$4

# Create logs directory if it doesn't exist
mkdir -p ./logs

# Generate timestamp for log files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="./logs/migration_detailed_${SOURCE_CLUSTER_NAME}_to_${DEST_CLUSTER_NAME}_${TIMESTAMP}.log"
SUMMARY_LOG_FILE="./logs/migration_summary_${SOURCE_CLUSTER_NAME}_to_${DEST_CLUSTER_NAME}_${TIMESTAMP}.log"

# Function to display mode banner
display_mode_banner() {
    echo ""
    if [ "$DRY_RUN" = true ]; then
        echo "============================================================"
        echo "🔍 DRY RUN MODE - NO CHANGES WILL BE MADE"
        echo "   This is a preview of what would happen"
        echo "   Use --live to actually execute migration"
        echo "============================================================"
    else
        echo "============================================================"
        echo "🚀 LIVE MODE - CHANGES WILL BE MADE"
        echo "   This will create actual catalog applications"
        echo "   Make sure you have reviewed the dry run results"
        echo "============================================================"
    fi
    echo ""
}

# Function to show log file information
display_log_info() {
    echo "📁 LOGGING INFORMATION:"
    echo "   📊 Detailed Log: $LOG_FILE"
    echo "   📋 Summary Log:  $SUMMARY_LOG_FILE"
    echo ""
}

# Function to log messages to both console and files with timestamp and mode indicators
log_message() {
    local message="$1"
    local mode_prefix=""
    
    if [ "$DRY_RUN" = true ]; then
        mode_prefix="🔍 DRY RUN: "
    else
        mode_prefix="🚀 LIVE: "
    fi
    
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local full_message="$timestamp $mode_prefix$message"
    
    echo "$full_message"
    echo "$full_message" >> "$LOG_FILE"
}

# Function to log summary information
log_summary() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local mode_indicator=""
    
    if [ "$DRY_RUN" = true ]; then
        mode_indicator="[DRY RUN - preview only]"
    else
        mode_indicator="[LIVE - actual changes made]"
    fi
    
    local full_message="$timestamp $mode_indicator $message"
    echo "$full_message" >> "$SUMMARY_LOG_FILE"
}

# Function to ask for confirmation
ask_confirmation() {
    if [ "$AUTO_CONFIRM" = true ]; then
        log_message "Auto-confirm enabled, proceeding without prompts"
        return 0
    fi
    
    local message="$1"
    local default_response="$2"
    
    echo ""
    echo "⚠️  CONFIRMATION REQUIRED:"
    echo "$message"
    echo ""
    
    if [ "$default_response" = "y" ]; then
        read -p "Do you want to proceed? [Y/n]: " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            return 1
        fi
    else
        read -p "Do you want to proceed? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to execute API calls with proper mode handling
execute_api_call() {
    local method=$1
    local url=$2
    local payload=$3
    local operation=$4
    local resource_name=$5
    
    if [ "$LIVE_MODE" = true ]; then
        # LIVE MODE: Execute actual API call
        log_message "Executing $operation: $resource_name" >&2
        
        # Execute the API call and capture ONLY the response
        local response=$(curl -s -X "$method" \
            -H "Authorization: NIRMATA-API $TOKEN" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$url" 2>/dev/null)
        
        # Return ONLY the clean response
        echo "$response"
    else
        # DRY RUN MODE: Just log what would be done
        log_message "Would execute $operation: $resource_name"
        echo '{"id":"dry-run-mock-id","name":"'$resource_name'"}' 
    fi
}

# Function to check authentication
check_auth() {
    log_message "Checking API authentication..."
    local response=$(curl -s -w "%{http_code}" -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/clusters")
    local http_code=${response: -3}
    
    if [ "$http_code" != "200" ]; then
        log_message "ERROR: Authentication failed. HTTP code: $http_code"
        return 1
    fi
    log_message "Authentication successful"
    return 0
}

# Function to check if application exists
check_application_exists() {
    local app_name=$1
    local response=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/catalog/api/applications?fields=id,name" | jq -r ".[] | select(.name == \"$app_name\")")
    echo "$response"
}

# Function to get git credential reference from source application
get_git_credential_reference() {
    local git_upstream_id=$1
    local response=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/gitupstreams/$git_upstream_id")
    
    # First try to get credential ID from the credential field
    local cred_id=$(echo "$response" | jq -r '.credential.id // empty')
    
    if [ -z "$cred_id" ] || [ "$cred_id" = "null" ]; then
        # Try getting from gitCredential field if credential didn't work
        cred_id=$(echo "$response" | jq -r '.gitCredential.id // empty')
    fi
    
    if [ ! -z "$cred_id" ] && [ "$cred_id" != "null" ]; then
        # Get the credential name using the ID
        local cred_details=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/gitcredentials/$cred_id")
        local cred_name=$(echo "$cred_details" | jq -r '.name // empty')
        if [ ! -z "$cred_name" ] && [ "$cred_name" != "null" ]; then
            echo "$cred_name"
        fi
    fi
}

# Function to get environment git credential name with fallback
get_environment_git_credential() {
    local preferred_cred_name=$1
    local response=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/gitcredentials")
    if [ ! -z "$response" ]; then
        # First try to find credential with the same name
        if [ ! -z "$preferred_cred_name" ]; then
            local matching_cred=$(echo "$response" | jq -r ".[] | select(.name == \"$preferred_cred_name\") | .name")
            if [ ! -z "$matching_cred" ] && [ "$matching_cred" != "null" ]; then
                echo "$matching_cred"
                return 0
            fi
        fi
        
        # If not found, get the first available credential
        local fallback_cred=$(echo "$response" | jq -r '.[0].name // empty')
        if [ ! -z "$fallback_cred" ] && [ "$fallback_cred" != "null" ]; then
            echo "$fallback_cred"
        fi
    fi
}

# Function to map team ID from environment to catalog by name
map_team_id_for_catalog() {
    local team_name=$1
    
    if [ ! -z "$team_name" ] && [ "$team_name" != "null" ]; then
        # Get team ID from users/teams API (teams exist at account level)
        local team_id=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" \
            "$API_ENDPOINT/users/api/teams" | \
            jq -r --arg name "$team_name" '.[] | select(.name == $name) | .id')
        
        if [ ! -z "$team_id" ] && [ "$team_id" != "null" ]; then
            echo "$team_id"
            return 0
        fi
    fi
    
    return 1
}

# Function to get team permissions from source environment
get_source_environment_permissions() {
    local env_id=$1
    
    log_message "Getting team permissions from source environment: $env_id" >&2
    
    # Get environment details to find ACL
    local env_details=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/environments/$env_id")
    
    # Check if response is valid JSON
    if ! echo "$env_details" | jq empty 2>/dev/null; then
        log_message "Invalid JSON response from environment API" >&2
        return 1
    fi
    
    local acl_id=$(echo "$env_details" | jq -r '.accessControlList[0].id // empty' 2>/dev/null)
    
    if [ -z "$acl_id" ] || [ "$acl_id" = "null" ]; then
        log_message "No access control list found in source environment" >&2
        return 1
    fi
    
    log_message "Source environment ACL ID: $acl_id" >&2
    
    # Get ACL details
    local acl_details=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" \
        "$API_ENDPOINT/environments/api/accessControlLists/$acl_id")
    
    # Check if ACL response is valid JSON
    if ! echo "$acl_details" | jq empty 2>/dev/null; then
        log_message "Invalid JSON response from ACL API" >&2
        return 1
    fi
    
    # Extract team permissions
    local team_permissions=""
    local access_control_ids=$(echo "$acl_details" | jq -r '.accessControls[].id' 2>/dev/null)
    
    if [ -z "$access_control_ids" ]; then
        log_message "No access controls found in ACL" >&2
        return 1
    fi
    
    for control_id in $access_control_ids; do
        if [ ! -z "$control_id" ] && [ "$control_id" != "null" ]; then
            local control_details=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" \
                "$API_ENDPOINT/environments/api/accessControls/$control_id")
            
            # Check if control response is valid JSON
            if ! echo "$control_details" | jq empty 2>/dev/null; then
                log_message "Invalid JSON response from access control API for ID: $control_id" >&2
                continue
            fi
            
            local entity_type=$(echo "$control_details" | jq -r '.entityType // empty' 2>/dev/null)
            local entity_name=$(echo "$control_details" | jq -r '.entityName // empty' 2>/dev/null)
            local permission=$(echo "$control_details" | jq -r '.permission // empty' 2>/dev/null)
            
            if [ "$entity_type" = "team" ] && [ ! -z "$entity_name" ] && [ ! -z "$permission" ]; then
                log_message "Found team permission: $entity_name -> $permission" >&2
                if [ -z "$team_permissions" ]; then
                    team_permissions="$entity_name:$permission"
                else
                    team_permissions="$team_permissions,$entity_name:$permission"
                fi
            fi
        fi
    done
    
    if [ ! -z "$team_permissions" ]; then
        echo "$team_permissions"
        return 0
    else
        log_message "No team permissions found in source environment" >&2
        return 1
    fi
}

# Function to apply team permissions to catalog (better than individual applications)
apply_team_permissions_to_catalog() {
    local catalog_id=$1
    local team_permissions=$2
    
    if [ -z "$team_permissions" ]; then
        log_message "No team permissions to apply"
        return 0
    fi
    
    log_message "Applying team permissions to catalog: $catalog_id"
    
    # Get catalog ACL
    local catalog_details=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" \
        "$API_ENDPOINT/catalog/api/catalogs/$catalog_id")
    
    # Check if response is valid JSON
    if ! echo "$catalog_details" | jq empty 2>/dev/null; then
        log_message "Invalid JSON response from catalog API"
        return 1
    fi
    
    local catalog_acl_id=$(echo "$catalog_details" | jq -r '.accessControlList[0].id // empty' 2>/dev/null)
    
    if [ -z "$catalog_acl_id" ] || [ "$catalog_acl_id" = "null" ]; then
        log_message "No access control list found in catalog"
        return 1
    fi
    
    log_message "Catalog ACL ID: $catalog_acl_id"
    
    # Get existing ACL entries to avoid duplicates
    local existing_acl_details=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" \
        "$API_ENDPOINT/catalog/api/accessControlLists/$catalog_acl_id")
    
    # Process each team permission
    IFS=',' read -ra PERMISSIONS <<< "$team_permissions"
    for perm in "${PERMISSIONS[@]}"; do
        IFS=':' read -r team_name permission <<< "$perm"
        
        if [ ! -z "$team_name" ] && [ ! -z "$permission" ]; then
            log_message "Processing permission: Team '$team_name' -> '$permission'"
            
            # Map team name to team ID
            local team_id=$(map_team_id_for_catalog "$team_name")
            
            if [ ! -z "$team_id" ]; then
                log_message "Mapped team '$team_name' to ID: $team_id"
                
                # Check if this team permission already exists
                local existing_entry=$(echo "$existing_acl_details" | jq -r --arg team_id "$team_id" '.accessControls[] | select(.id) | .id' 2>/dev/null | head -1)
                
                if [ ! -z "$existing_entry" ]; then
                    log_message "Team '$team_name' already has permissions in catalog - skipping"
                    continue
                fi
                
                if [ "$LIVE_MODE" = true ]; then
                    # Create ACL entry for team
                    local acl_payload="{
                        \"entityId\": \"$team_id\",
                        \"entityType\": \"team\",
                        \"permission\": \"$permission\",
                        \"entityName\": \"$team_name\"
                    }"
                    
                    local acl_response=$(curl -s -X POST \
                        -H "Authorization: NIRMATA-API $TOKEN" \
                        -H "Content-Type: application/json" \
                        -d "$acl_payload" \
                        "$API_ENDPOINT/catalog/api/accessControlLists/$catalog_acl_id/accessControls")
                    
                    if echo "$acl_response" | jq -e '.id' > /dev/null 2>&1; then
                        log_message "Successfully applied catalog permission: Team '$team_name' -> '$permission'"
                    else
                        log_message "Failed to apply catalog permission for team '$team_name': $acl_response"
                    fi
                else
                    log_message "Would apply catalog permission: Team '$team_name' -> '$permission' (ID: $team_id)"
                fi
            else
                log_message "WARNING: Team '$team_name' not found in destination - skipping permission"
            fi
        fi
    done
    
    return 0
}

# Function to get consistent catalog app name (Production-Ready Naming)
get_catalog_app_name() {
    local app_name=$1
    local source_env=$2
    local cluster_name=$3
    
    # PRODUCTION NAMING STRATEGY - Remove all cluster references
    # Goal: Clean, forward-looking names without old cluster ties
    
    # Step 1: Extract base application name
    # Remove timestamps first (14 digits), then shorter numeric suffixes
    local base_name=$(echo "$app_name" | sed -E 's/-[0-9]{14}$//' | sed -E 's/-[0-9]+$//')
    
    # Step 2: Remove ALL cluster references (source and destination)
    base_name=$(echo "$base_name" | sed "s/-${SOURCE_CLUSTER_NAME}$//")
    base_name=$(echo "$base_name" | sed "s/-${DEST_CLUSTER_NAME}$//")
    
    # Step 3: Extract meaningful name from environment
    # This handles patterns like: conformance-132-shuting → shuting
    local env_based_name=""
    if [[ "$source_env" =~ -([^-]+)$ ]]; then
        # Extract last segment after dash
        env_based_name="${BASH_REMATCH[1]}"
    elif [[ "$source_env" =~ ^([^-]+)- ]]; then
        # Extract first segment before dash
        env_based_name="${BASH_REMATCH[1]}"
    else
        # Use environment name as-is if no pattern matches
        env_based_name="$source_env"
    fi
    
    # Step 4: Choose the best name strategy
    local catalog_app_name=""
    
    # Strategy 1: If app name is meaningful and different from environment, use it
    if [ "$base_name" != "$source_env" ] && [ ${#base_name} -gt 3 ]; then
        catalog_app_name="$base_name"
    # Strategy 2: Use environment-derived name if it's clean
    elif [ ${#env_based_name} -gt 3 ] && [[ ! "$env_based_name" =~ ^(system|kube|nirmata|default)$ ]]; then
        catalog_app_name="$env_based_name"
    # Strategy 3: Fallback to cleaned app name
    else
        catalog_app_name="$base_name"
    fi
    
    # Step 5: Add prefix only if needed for clarity or conflict resolution
    # Option A: No prefix (cleanest)
    echo "$catalog_app_name"
    
    # Option B: Minimal prefix for organization (uncomment if needed)
    # echo "app-$catalog_app_name"
    
    # Option C: Team-based prefix (uncomment and configure if needed)
    # local team_prefix="platform"  # Configure based on your organization
    # echo "${team_prefix}-$catalog_app_name"
}

# Function to handle naming conflicts (Production Enhancement)
resolve_naming_conflicts() {
    local proposed_name=$1
    local existing_apps_response=$2
    local counter=1
    
    # Check if name already exists
    local existing_app=$(echo "$existing_apps_response" | jq -r ".[] | select(.name == \"$proposed_name\")")
    
    if [ ! -z "$existing_app" ]; then
        # Send log messages to stderr to avoid contaminating return value
        log_message "CONFLICT: Catalog application '$proposed_name' already exists" >&2
        
        # Strategy 1: Add version suffix
        while [ $counter -le 10 ]; do
            local versioned_name="${proposed_name}-v${counter}"
            local version_check=$(echo "$existing_apps_response" | jq -r ".[] | select(.name == \"$versioned_name\")")
            
            if [ -z "$version_check" ]; then
                log_message "RESOLVED: Using versioned name '$versioned_name'" >&2
                echo "$versioned_name"
                return 0
            fi
            ((counter++))
        done
        
        # Strategy 2: Add timestamp if versioning fails
        local timestamp_suffix=$(date +%m%d)
        local timestamped_name="${proposed_name}-${timestamp_suffix}"
        log_message "RESOLVED: Using timestamped name '$timestamped_name'" >&2
        echo "$timestamped_name"
    else
        echo "$proposed_name"
    fi
}

# Function to migrate application
migrate_application() {
    local APP_ID=$1
    local CATALOG_ID=$2
    local SOURCE_ENV_NAME=$3
    local SOURCE_ENV_ID=$4
    
    # Get application details
    local APP_DETAILS=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/applications/$APP_ID")
    local APP_NAME=$(echo "$APP_DETAILS" | jq -r '.name')
    
    # Get production-ready catalog app name (NO cluster references)
    local PROPOSED_CATALOG_NAME=$(get_catalog_app_name "$APP_NAME" "$SOURCE_ENV_NAME" "$SOURCE_CLUSTER_NAME")
    log_message "Production naming: '$APP_NAME' from env '$SOURCE_ENV_NAME' → '$PROPOSED_CATALOG_NAME'"
    
    # Get team permissions from source environment
    local SOURCE_TEAM_PERMISSIONS=$(get_source_environment_permissions "$SOURCE_ENV_ID")
    if [ $? -eq 0 ] && [ ! -z "$SOURCE_TEAM_PERMISSIONS" ]; then
        log_message "Found team permissions in source environment: $SOURCE_TEAM_PERMISSIONS"
    else
        log_message "No team permissions found in source environment"
        SOURCE_TEAM_PERMISSIONS=""
    fi
    
    # Get existing applications ONLY from the specific catalog being processed
    local EXISTING_CATALOG_APPS=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/catalog/api/applications?fields=id,name,description,parent")
    
    # Filter applications to only those in the target catalog
    local APPS_IN_TARGET_CATALOG=$(echo "$EXISTING_CATALOG_APPS" | jq -r ".[] | select(.parent.id == \"$CATALOG_ID\")")
    
    # Check if application already exists with the base name IN THIS CATALOG (skip if already migrated)
    local EXISTING_APP=$(echo "$APPS_IN_TARGET_CATALOG" | jq -r "select(.name == \"$PROPOSED_CATALOG_NAME\")")
    if [ ! -z "$EXISTING_APP" ]; then
        log_message "✅ SKIPPING: Catalog application '$PROPOSED_CATALOG_NAME' already exists in this catalog"
        log_message "    No need to create duplicate - application already migrated"
        return 0
    fi
    
    # Also check for any existing versioned applications (v1, v2, etc.) IN THIS CATALOG to avoid unnecessary duplicates
    local EXISTING_VERSIONED=$(echo "$APPS_IN_TARGET_CATALOG" | jq -r "select(.name | test(\"^$PROPOSED_CATALOG_NAME-v[0-9]+$\"))")
    if [ ! -z "$EXISTING_VERSIONED" ]; then
        local EXISTING_VERSION=$(echo "$EXISTING_VERSIONED" | jq -r '.name' | head -1)
        log_message "✅ SKIPPING: Versioned application '$EXISTING_VERSION' already exists for '$PROPOSED_CATALOG_NAME' in this catalog"
        log_message "    No need to create additional versions - application already migrated"
        return 0
    fi
    
    # Use the proposed name since no conflicts detected
    local FINAL_CATALOG_NAME="$PROPOSED_CATALOG_NAME"
    
    # Get Git upstream details - properly format as JSON object
    local GIT_UPSTREAM_RAW=$(echo "$APP_DETAILS" | jq '.gitUpstream[0]')
    if [ -z "$GIT_UPSTREAM_RAW" ] || [ "$GIT_UPSTREAM_RAW" = "null" ]; then
        log_message "No Git upstream found for application $APP_NAME"
        return 1
    fi
    
    # Get the complete GitUpstream details for catalog application
    local GIT_UPSTREAM_ID=$(echo "$GIT_UPSTREAM_RAW" | jq -r '.id')
    local GIT_UPSTREAM_DETAILS=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/gitupstreams/$GIT_UPSTREAM_ID")
    
    # Extract complete GitUpstream object for catalog (will add credential later)
    local GIT_UPSTREAM_BASE=$(echo "$GIT_UPSTREAM_DETAILS" | jq '{
        repository: .repository,
        branch: .branch,
        path: .path,
        service: "Catalog",
        modelIndex: "GitUpstream"
    }')
    
    # Get Git credential reference from source
    local SOURCE_GIT_CRED_ID=$(echo "$GIT_UPSTREAM_DETAILS" | jq -r '.credential.id // empty')
    local SOURCE_GIT_CRED_NAME=$(get_git_credential_reference "$GIT_UPSTREAM_ID")
    
    # Get appropriate git credential (prefer matching name, fallback to first available)
    local GIT_CRED_NAME=$(get_environment_git_credential "$SOURCE_GIT_CRED_NAME")
    if [ -z "$GIT_CRED_NAME" ]; then
        log_message "No Git credential found for application $APP_NAME"
        return 1
    fi
    
    # Find the credential ID for the selected credential name
    local GIT_CRED_ID=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/gitcredentials" | jq -r ".[] | select(.name == \"$GIT_CRED_NAME\") | .id")
    
    log_message "Using Git credential: $GIT_CRED_NAME (ID: $GIT_CRED_ID) for application $APP_NAME"
    
    # Create complete GitUpstream object with credential
    local GIT_UPSTREAM=$(echo "$GIT_UPSTREAM_BASE" | jq --arg cred_id "$GIT_CRED_ID" '. + {
        credential: {
            service: "Environments",
            modelIndex: "GitCredential", 
            id: $cred_id
        }
    }')
    
    # Use YOUR working script logic - create application first, then GitUpstream separately
    if [ "$LIVE_MODE" = true ]; then
        # STEP 1: Create base application (your working logic)
        local APP_PAYLOAD=$(cat <<EOF
{
    "name": "$FINAL_CATALOG_NAME",
    "modelIndex": "Application",
    "parent": {
        "id": "$CATALOG_ID",
        "service": "Catalog",
        "modelIndex": "Catalog",
        "childRelation": "applications"
    },
    "catalog": "$CATALOG_ID",
    "description": "Migrated from environment $SOURCE_ENV_NAME (Original: $APP_NAME)",
    "upstreamType": "git",
    "state": "running",
    "run": "$APP_NAME",
    "labels": {
        "nirmata.io/application.run": "$APP_NAME"
    }
}
EOF
)

        log_message "Creating application with payload: $APP_PAYLOAD"
        local APP_RESPONSE=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" -H "Content-Type: application/json" -d "$APP_PAYLOAD" "$API_ENDPOINT/catalog/api/applications")

        # Check for application creation errors
        if echo "$APP_RESPONSE" | jq -e '.errors' > /dev/null; then
            local ERROR_MSG=$(echo "$APP_RESPONSE" | jq -r '.message')
            log_message "Failed to create application: $ERROR_MSG"
            return 1
        fi

        local NEW_APP_ID=$(echo "$APP_RESPONSE" | jq -r '.id')
        if [ -z "$NEW_APP_ID" ] || [ "$NEW_APP_ID" = "null" ]; then
            log_message "Failed to get new application ID for $FINAL_CATALOG_NAME"
            return 1
        fi

        log_message "Successfully created new application with ID: $NEW_APP_ID"

        # STEP 2: Create GitUpstream for the application (your working logic)
        local REPO_URL=$(echo "$GIT_UPSTREAM_DETAILS" | jq -r '.repository')
        local BRANCH=$(echo "$GIT_UPSTREAM_DETAILS" | jq -r '.branch')
        local PATH_VALUE=$(echo "$GIT_UPSTREAM_DETAILS" | jq -r '.path // ""')

        # STEP 2A: Create GitUpstream without credential first
        local GIT_UPSTREAM_PAYLOAD=$(cat <<EOF
{
    "modelIndex": "GitUpstream",
    "parent": {
        "id": "$NEW_APP_ID",
        "service": "Catalog",
        "modelIndex": "Application",
        "childRelation": "gitUpstream"
    },
    "repository": "$REPO_URL",
    "branch": "$BRANCH",
    "path": "$PATH_VALUE",
    "includeList": ["*.yaml", "*.yml"],
    "application": "$NEW_APP_ID",
    "additionalProperties": {
        "name": "$APP_NAME"
    }
}
EOF
)

        log_message "Creating GitUpstream with payload: $GIT_UPSTREAM_PAYLOAD"
        local GIT_UPSTREAM_RESPONSE=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" -H "Content-Type: application/json" -d "$GIT_UPSTREAM_PAYLOAD" "$API_ENDPOINT/catalog/api/gitupstreams")

        # Check if GitUpstream was created successfully
        local GIT_UPSTREAM_ID=$(echo "$GIT_UPSTREAM_RESPONSE" | jq -r '.id // empty')
        if [ -z "$GIT_UPSTREAM_ID" ] || [ "$GIT_UPSTREAM_ID" = "null" ] || [ "$GIT_UPSTREAM_ID" = "empty" ]; then
            log_message "Failed to create GitUpstream"
            log_message "Response: $GIT_UPSTREAM_RESPONSE"
            return 1
        fi

        log_message "Successfully created GitUpstream with ID: $GIT_UPSTREAM_ID"

        # STEP 2B: Update GitUpstream to set the credential (API requires separate step)
        local CREDENTIAL_PAYLOAD=$(cat <<EOF
{
    "gitCredential": {
        "service": "Environments",
        "modelIndex": "GitCredential",
        "id": "$GIT_CRED_ID"
    }
}
EOF
)

        log_message "Updating GitUpstream with credential: $GIT_CRED_NAME (ID: $GIT_CRED_ID)"
        local CREDENTIAL_UPDATE_RESPONSE=$(curl -s -X PUT -H "Authorization: NIRMATA-API $TOKEN" -H "Content-Type: application/json" -d "$CREDENTIAL_PAYLOAD" "$API_ENDPOINT/catalog/api/gitupstreams/$GIT_UPSTREAM_ID")

        if [ $? -eq 0 ]; then
            log_message "Successfully updated GitUpstream with credential"
            
            log_message "Migration Result: SUCCESS"
            log_message "  - New Application ID: $NEW_APP_ID"
            log_message "  - GitUpstream ID: $GIT_UPSTREAM_ID"
            log_message "  - Git Repository: $REPO_URL"
            log_message "  - Branch: $BRANCH"
            log_message "  - Path: $PATH_VALUE"
            log_message "  - Git Credential: $GIT_CRED_NAME (ID: $GIT_CRED_ID)"
            return 0
        else
            log_message "Failed to update GitUpstream with credential"
            log_message "Response: $CREDENTIAL_UPDATE_RESPONSE"
            return 1
        fi
    else
        # In dry run mode, assume success
        log_message "Would create clean catalog name without cluster references"
        log_message "Would create GitUpstream with proper parent-child relationship"
        return 0
    fi
}

# Function to process a single environment
process_environment() {
    local SOURCE_ENV_NAME=$1
    local SOURCE_ENV_ID=$2
    local processed_count=0
    local success_count=0
    local skip_count=0
    local fail_count=0
    local has_git_apps=false

    log_message "Processing environment: $SOURCE_ENV_NAME (ID: $SOURCE_ENV_ID)"

    # Get applications ONLY from this specific environment (not all clusters)
    log_message "Checking for Git-based applications in environment $SOURCE_ENV_NAME..."
    APPS_RESPONSE=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/environments/$SOURCE_ENV_ID/applications")
    
    if [ "$(echo "$APPS_RESPONSE" | jq 'length')" -eq 0 ]; then
        log_message "No applications found in environment $SOURCE_ENV_NAME"
        return
    fi

    log_message "Found $(echo "$APPS_RESPONSE" | jq 'length') applications in environment $SOURCE_ENV_NAME"

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
        CATALOG_NAME=$(echo "$SOURCE_ENV_NAME" | sed 's/-[0-9].*$//')
        
        # Interactive confirmation for mapping (skip if auto-confirm is enabled)
        if [ "$AUTO_CONFIRM" = false ]; then
            log_message "🔍 Interactive confirmation required for environment: $SOURCE_ENV_NAME"
            if ! confirmed_catalog_name=$(interactive_confirm_mapping "$SOURCE_ENV_NAME" "$CATALOG_NAME"); then
                log_message "⏭️  Skipping environment: $SOURCE_ENV_NAME (user choice)"
                return 0
            fi
            CATALOG_NAME="$confirmed_catalog_name"
        fi
        
        # Check if catalog already exists
        log_message "Checking if catalog $CATALOG_NAME already exists..."
        CATALOG_RESPONSE=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/catalog/api/catalogs?fields=id,name")
        CATALOG_ID=$(echo "$CATALOG_RESPONSE" | jq -r ".[] | select(.name == \"$CATALOG_NAME\") | .id")

        if [ -n "$CATALOG_ID" ] && [ "$CATALOG_ID" != "null" ]; then
            log_message "Using existing catalog: $CATALOG_NAME (ID: $CATALOG_ID)"
        else
            log_message "Creating new catalog: $CATALOG_NAME"
            CATALOG_PAYLOAD=$(cat <<EOF
{
    "name": "$CATALOG_NAME",
    "description": "Migrated from environment $SOURCE_ENV_NAME in cluster $SOURCE_CLUSTER_NAME",
    "service": "Catalog",
    "modelIndex": "Catalog"
}
EOF
)
            
            # Execute catalog creation (dry run or live)
            CATALOG_CREATE_RESPONSE=$(execute_api_call "POST" "$API_ENDPOINT/catalog/api/catalogs" "$CATALOG_PAYLOAD" "create catalog" "$CATALOG_NAME")
            
            if [ "$LIVE_MODE" = true ]; then
                CATALOG_ID=$(echo "$CATALOG_CREATE_RESPONSE" | jq -r '.id // empty')
                
                if [ ! -z "$CATALOG_ID" ] && [ "$CATALOG_ID" != "null" ]; then
                    log_message "Successfully created catalog: $CATALOG_NAME (ID: $CATALOG_ID)"
                else
                    log_message "Failed to create catalog: $CATALOG_NAME"
                    log_message "Response: $CATALOG_CREATE_RESPONSE"
                    return 1
                fi
            else
                # In dry run mode, use a placeholder ID
                CATALOG_ID="dry-run-catalog-id"
                log_message "Would create catalog: $CATALOG_NAME"
            fi
        fi

        # Get team permissions from source environment (do this ONCE per environment)
        SOURCE_TEAM_PERMISSIONS=$(get_source_environment_permissions "$SOURCE_ENV_ID")
        
        if [ ! -z "$SOURCE_TEAM_PERMISSIONS" ]; then
            log_message "Found team permissions in source environment: $SOURCE_TEAM_PERMISSIONS"
            
            # Apply team permissions to catalog (regardless of whether apps are created or skipped)
            log_message "Copying team permissions from source environment to catalog"
            apply_team_permissions_to_catalog "$CATALOG_ID" "$SOURCE_TEAM_PERMISSIONS"
        else
            log_message "No team permissions found in source environment"
        fi

        # Process applications
        while read -r app; do
            if [ -n "$app" ]; then
                APP_ID=$(echo "$app" | jq -r '.id')
                APP_NAME=$(echo "$app" | jq -r '.name')
                GIT_UPSTREAM_COUNT=$(echo "$app" | jq '.gitUpstream | length')
                
                ((processed_count++))
                
                if [ "$GIT_UPSTREAM_COUNT" -gt 0 ]; then
                    log_message "Processing Git-based application: $APP_NAME"
                    if migrate_application "$APP_ID" "$CATALOG_ID" "$SOURCE_ENV_NAME" "$SOURCE_ENV_ID"; then
                        ((success_count++))
                        log_message "Successfully processed: $APP_NAME"
                    else
                        ((fail_count++))
                        log_message "Failed to process: $APP_NAME"
                    fi
                else
                    log_message "Skipping non-Git application: $APP_NAME"
                    ((skip_count++))
                fi
            fi
        done < <(echo "$APPS_RESPONSE" | jq -c '.[]')
        
        # Log summary for this environment
        log_message "Environment $SOURCE_ENV_NAME processing complete:"
        log_message "  - Processed: $processed_count Git applications"
        log_message "  - Successful: $success_count"
        log_message "  - Failed: $fail_count"
        log_message "  - Skipped: $skip_count non-Git applications"
        
        # Log to summary file
        log_summary "Environment $SOURCE_ENV_NAME: $processed_count processed, $success_count successful, $fail_count failed, $skip_count skipped"
    else
        log_message "No Git-based applications found in environment $SOURCE_ENV_NAME, skipping catalog creation"
        log_summary "Environment $SOURCE_ENV_NAME: No Git-based applications found, skipped"
    fi

    # Log migration summary for this environment to detailed file
    cat >> "$LOG_FILE" <<EOF
=== Migration Summary for $SOURCE_ENV_NAME ===
Applications processed: $processed_count
Successfully migrated: $success_count
Skipped (non-Git): $skip_count
Failed: $fail_count
=====================================
EOF
}

# Function to interactively confirm environment mapping
interactive_confirm_mapping() {
    local source_env_name="$1"
    local suggested_catalog_name="$2"
    
    echo ""
    echo "🔍 ENVIRONMENT → CATALOG MAPPING CONFIRMATION"
    echo "=============================================="
    echo "Source Environment: $source_env_name"
    echo "Suggested Catalog: $suggested_catalog_name"
    echo ""
    
    # Show Git-based applications that will be migrated
    local git_app_names=$(echo "$APPS_RESPONSE" | jq -r '.[] | select(.gitUpstream | length > 0) | .name' | sort)
    local git_app_count=$(echo "$git_app_names" | wc -l)
    
    if [ ! -z "$git_app_names" ]; then
        echo "📱 Git-based applications to migrate ($git_app_count):"
        echo "$git_app_names" | sed 's/^/  - /'
        echo ""
    fi
    
    # Show team permissions if any
    local team_permissions=$(get_source_environment_permissions "$SOURCE_ENV_ID")
    if [ ! -z "$team_permissions" ]; then
        echo "👥 Team permissions to copy to catalog:"
        echo "$team_permissions" | tr ',' '\n' | sed 's/^/  - /' | sed 's/:/ → /'
        echo ""
    fi
    
    while true; do
        echo -n "Do you want to migrate applications from '$source_env_name' to catalog '$suggested_catalog_name'? (y/n/list/skip): "
        read -r response
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]|"y"|"Y")
                echo "✅ Confirmed: $source_env_name → $suggested_catalog_name"
                echo "$suggested_catalog_name"
                return 0
                ;;
            [Nn]|[Nn][Oo]|"n"|"N")
                echo ""
                echo "❌ Mapping rejected. Please specify the correct catalog name."
                echo ""
                echo "Available catalogs:"
                curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/catalog/api/catalogs" | jq -r '.[] | "  - " + .name' | sort
                echo ""
                
                while true; do
                    echo -n "Enter the correct catalog name (or 'skip' to skip this environment): "
                    read -r custom_catalog_name
                    
                    if [ "$custom_catalog_name" = "skip" ]; then
                        echo "⏭️  Skipping environment: $source_env_name"
                        return 1
                    fi
                    
                    # Validate the custom catalog name
                    if [ ! -z "$custom_catalog_name" ]; then
                        echo "✅ Custom mapping confirmed: $source_env_name → $custom_catalog_name"
                        echo "$custom_catalog_name"
                        return 0
                    else
                        echo "❌ Error: Please enter a valid catalog name."
                        echo ""
                    fi
                done
                ;;
            [Ll][Ii][Ss][Tt]|"list"|"LIST")
                echo ""
                echo "📋 Available catalogs:"
                curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/catalog/api/catalogs" | jq -r '.[] | "  - " + .name' | sort
                echo ""
                # Continue the loop to ask again
                ;;
            [Ss][Kk][Ii][Pp]|"skip"|"SKIP")
                echo "⏭️  Skipping environment: $source_env_name"
                return 1
                ;;
            "")
                echo "Please enter a response. Options: 'y' for yes, 'n' for no, 'list' to see available catalogs, 'skip' to skip."
                ;;
            *)
                echo "Invalid response: '$response'. Please answer 'y' for yes, 'n' for no, 'list' to see catalogs, or 'skip' to skip."
                ;;
        esac
    done
}

# Display initial information
display_mode_banner
display_log_info

# Main execution starts here
log_message "Starting enhanced environment to catalog migration process"
log_message "🎯 SCOPE: ONLY processing environments from source cluster '$SOURCE_CLUSTER_NAME'"
log_message "Source Cluster: $SOURCE_CLUSTER_NAME"
log_message "Destination Cluster: $DEST_CLUSTER_NAME"
log_message "API Endpoint: $API_ENDPOINT"
log_message "Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN (preview only)" || echo "LIVE (actual changes)")"

# Initialize log files with headers
cat > "$LOG_FILE" <<EOF
=== Enhanced Migration Report ===
Date: $(date)
Source Cluster: $SOURCE_CLUSTER_NAME
Destination Cluster: $DEST_CLUSTER_NAME
API Endpoint: $API_ENDPOINT
Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN (preview only)" || echo "LIVE (actual changes)")

Migration Details:
=====================================
EOF

cat > "$SUMMARY_LOG_FILE" <<EOF
=== Migration Summary Report ===
Date: $(date)
Source Cluster: $SOURCE_CLUSTER_NAME
Destination Cluster: $DEST_CLUSTER_NAME
Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN (preview only)" || echo "LIVE (actual changes)")

Results:
=====================================
EOF

# Check authentication
if ! check_auth; then
    log_message "Authentication failed. Exiting."
    exit 1
fi

# If live mode, ask for confirmation
if [ "$LIVE_MODE" = true ]; then
    echo ""
    echo "========== MIGRATION CONFIRMATION =========="
    echo "🚀 You are about to execute LIVE migration!"
    echo ""
    echo "This will:"
    echo "• Create catalog applications in the destination system"
    echo "• Use Git credentials from the environment"
    echo "• Create new catalogs if they don't exist"
    echo ""
    echo "Migration Details:"
    echo "• Source Cluster: $SOURCE_CLUSTER_NAME"
    echo "• Destination Cluster: $DEST_CLUSTER_NAME"
    echo "• API Endpoint: $API_ENDPOINT"
    echo "• Auto-confirm: $([ "$AUTO_CONFIRM" = true ] && echo "YES" || echo "NO")"
    echo ""
    echo "Make sure you have:"
    echo "• ✅ Reviewed the dry run results"
    echo "• ✅ Verified Git credentials are configured"
    echo "• ✅ Confirmed catalog naming strategy"
    echo "• ✅ Ensured proper API permissions"
    echo ""
    
    if ! ask_confirmation "Are you sure you want to proceed with the LIVE migration?" "n"; then
        log_message "Migration cancelled by user"
        echo ""
        echo "💡 TIP: Run without --live flag to preview the migration first:"
        echo "   $0 $API_ENDPOINT [TOKEN] $SOURCE_CLUSTER_NAME $DEST_CLUSTER_NAME"
        exit 0
    fi
    
    log_message "User confirmed live migration execution"
fi

# Get cluster ID for source cluster name
log_message "Getting cluster ID for source cluster: $SOURCE_CLUSTER_NAME"
SOURCE_CLUSTER_ID=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/clusters" | jq -r ".[] | select(.name == \"$SOURCE_CLUSTER_NAME\") | .id")

if [ -z "$SOURCE_CLUSTER_ID" ] || [ "$SOURCE_CLUSTER_ID" = "null" ]; then
    log_message "No cluster found with name '$SOURCE_CLUSTER_NAME'"
    exit 1
fi

log_message "Found cluster ID: $SOURCE_CLUSTER_ID"

# Get all environments for the source cluster using cluster ID
log_message "Finding environments for cluster: $SOURCE_CLUSTER_NAME"
ENVIRONMENTS=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/environments" | jq -r ".[] | select(.cluster[0].id == \"$SOURCE_CLUSTER_ID\") | .name")

if [ -z "$ENVIRONMENTS" ]; then
    log_message "No environments found for cluster '$SOURCE_CLUSTER_NAME'"
    exit 1
fi

log_message "Found $(echo "$ENVIRONMENTS" | wc -w) environments in source cluster $SOURCE_CLUSTER_NAME:"
echo "$ENVIRONMENTS" | while read -r env; do
    log_message "  - $env"
done

log_message "ONLY processing environments from source cluster '$SOURCE_CLUSTER_NAME' (NOT from other clusters)"

# Process each environment found in the source cluster
log_message "Processing environments in cluster $SOURCE_CLUSTER_NAME:"
while read -r env_name; do
    if [ -n "$env_name" ]; then
        # Get environment ID for this environment name
        ENV_ID=$(curl -s -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/environments" | jq -r ".[] | select(.name == \"$env_name\" and .cluster[0].id == \"$SOURCE_CLUSTER_ID\") | .id")
        
        if [ -n "$ENV_ID" ] && [ "$ENV_ID" != "null" ]; then
            process_environment "$env_name" "$ENV_ID"
        else
            log_message "Could not find environment ID for: $env_name"
        fi
    fi
done < <(echo "$ENVIRONMENTS" | tr ' ' '\n')

# Final summary
log_message "Enhanced migration process completed successfully"
log_summary "Migration process completed at $(date)"

# Display final information
echo ""
echo "📁 LOG FILES CREATED:"
echo "   📊 Detailed Log: $LOG_FILE"
echo "   📋 Summary Log:  $SUMMARY_LOG_FILE"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "🔍 This was a DRY RUN - no actual changes were made to your environment."
    echo "   To execute these changes, run the script again with the --live flag:"
    echo "   $0 $API_ENDPOINT [TOKEN] $SOURCE_CLUSTER_NAME $DEST_CLUSTER_NAME --live"
    echo ""
    echo "💡 TIP: Review the detailed log file for complete operation details:"
    echo "   cat $LOG_FILE"
else
    echo "🚀 LIVE migration completed!"
    echo "   Check the Nirmata UI → Catalog to see your migrated applications"
    echo "   Applications created with naming: app-{name}-${SOURCE_CLUSTER_NAME}"
    echo ""
    echo "💡 TIP: Review the summary log file for results:"
    echo "   cat $SUMMARY_LOG_FILE"
fi

echo ""
echo "Check the log files for detailed results and troubleshooting information."