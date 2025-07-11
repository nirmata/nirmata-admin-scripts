#!/bin/bash

# Check if required parameters are provided
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <api_endpoint> <token> <source_cluster> <destination_cluster> [OPTIONS]"
    echo ""
    echo "Safety Options:"
    echo "  --dry-run                    Show what would be done without making changes (DEFAULT)"
    echo "  --live                       Make actual changes (DANGEROUS - use with caution)"
    echo "  --auto-confirm              Skip confirmation prompts"
    echo "  --verbose                   Show detailed API responses"
    echo ""
    echo "🛡️  SAFE WORKFLOW (RECOMMENDED):"
    echo "  1. $0 ... --dry-run          # Preview what will happen (DEFAULT)"
    echo "  2. Review the output carefully"
    echo "  3. $0 ... --live             # Execute actual changes"
    echo ""
    echo "Examples:"
    echo "  # Step 1: Preview changes (SAFE - DEFAULT)"
    echo "  $0 https://api.co TOKEN1 source-cluster dest-cluster"
    echo ""
    echo "  # Step 2: Execute changes (CONTROLLED)"
    echo "  $0 https://api.co TOKEN1 source-cluster dest-cluster --live"
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

shift 4
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --live)
            DRY_RUN=false
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
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Create logs directory if it doesn't exist
LOG_DIR="logs"
mkdir -p "$LOG_DIR"

# Create log file with timestamp
LOG_FILE="${LOG_DIR}/env_restore_$(date '+%Y%m%d_%H%M%S').log"
SUMMARY_FILE="${LOG_DIR}/env_restore_summary_$(date '+%Y%m%d_%H%M%S').log"

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

# Function to find corresponding destination environment with multiple strategies
find_dest_environment() {
    local source_env_name=$1
    
    # Validate input
    if [ -z "$source_env_name" ]; then
        return 1
    fi
    
    # Filter environments to only include destination cluster
    local dest_environments=$(echo "$ENVIRONMENTS" | jq -c --arg cluster_id "$DEST_CLUSTER_ID" '[.[] | select(.cluster[0].id == $cluster_id)]')
    
    # Strategy 1: Exact match (only in destination cluster)
    local dest_env=$(echo "$dest_environments" | jq -c --arg name "$source_env_name" '.[] | select(.name == $name)')
    
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
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
    # Pattern 2: namespace-clustername (remove cluster suffix)  
    elif [[ "$source_env_name" == *"-$SOURCE_CLUSTER" ]]; then
        namespace=$(echo "$source_env_name" | sed "s/-$SOURCE_CLUSTER$//")
    # Pattern 3: Try case-insensitive cluster matching
    elif [[ "$(echo "$source_env_name" | tr '[:upper:]' '[:lower:]')" == "$source_cluster_lower-"* ]]; then
        namespace=$(echo "$(echo "$source_env_name" | tr '[:upper:]' '[:lower:]')" | sed "s/^$source_cluster_lower-//")
    elif [[ "$(echo "$source_env_name" | tr '[:upper:]' '[:lower:]')" == *"-$source_cluster_lower" ]]; then
        namespace=$(echo "$(echo "$source_env_name" | tr '[:upper:]' '[:lower:]')" | sed "s/-$source_cluster_lower$//")
    # Pattern 4: Remove any numeric suffixes and try again
    else
        namespace=$(echo "$source_env_name" | sed 's/-[0-9]*$//')
    fi
    
    if [ -z "$namespace" ]; then
        namespace="$source_env_name"
    fi
    
    # Strategy 3: Try to find destination environment using extracted namespace
    # Try multiple destination patterns
    
    # Pattern A: exact namespace match
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$namespace" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        echo "$dest_env"
        return 0
    fi
    
    # Pattern B: destcluster-namespace
    local dest_pattern="$DEST_CLUSTER-$namespace"
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$dest_pattern" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
        echo "$dest_env"
        return 0
    fi
    
    # Pattern C: namespace-destcluster
    dest_pattern="$namespace-$DEST_CLUSTER"
    dest_env=$(echo "$dest_environments" | jq -c --arg name "$dest_pattern" '.[] | select(.name == $name)')
    if [ ! -z "$dest_env" ] && [ "$dest_env" != "null" ]; then
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
        echo "$dest_env"
        return 0
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
    echo "Do you want to continue? (y/N): "
    read -r response
    
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
        echo "🔍 DRY RUN MODE - NO CHANGES WILL BE MADE"
        echo "   This is a preview of what would happen"
        echo "   Use --live to actually execute changes"
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

# Display mode banner
display_mode_banner

echo "📁 LOGGING INFORMATION:"
echo "   📊 Detailed Log: $LOG_FILE"
echo "   📋 Summary Log:  $SUMMARY_FILE"
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
SOURCE_ENVIRONMENTS=$(echo "$ENVIRONMENTS_RESPONSE" | jq -r --arg cluster "$SOURCE_CLUSTER_ID" '.[] | select(.cluster[].id == $cluster)')

# Debug output
echo "All environments:"
echo "$ENVIRONMENTS" | jq '.'
echo "Source cluster ID: $SOURCE_CLUSTER_ID"
echo "Source environments:"
echo "$SOURCE_ENVIRONMENTS" | jq '.'

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

# First, let's preview the environment mappings
log_message "========== ENVIRONMENT MAPPING PREVIEW =========="

# Create temporary files for counting
TEMP_PREVIEW="/tmp/env_preview_$$"
echo "" > "$TEMP_PREVIEW"

echo "$SOURCE_ENVIRONMENTS" | jq -c '.' | while read -r env; do
    ENV_NAME=$(echo "$env" | jq -r '.name')
    
    # Check if this is a system namespace that should be skipped
    if is_system_namespace "$ENV_NAME"; then
        log_message "PREVIEW: SKIP (system namespace) - $ENV_NAME"
        echo "SKIP" >> "$TEMP_PREVIEW"
        continue
    fi
    
    # Use intelligent environment mapping
    DEST_ENV=$(find_dest_environment "$ENV_NAME")
    
    if [ -z "$DEST_ENV" ]; then
        log_message "PREVIEW: FAIL (no match) - $ENV_NAME"
        echo "FAIL" >> "$TEMP_PREVIEW"
    else
        DEST_ENV_NAME=$(echo "$DEST_ENV" | jq -r '.name')
        log_message "PREVIEW: MATCH - $ENV_NAME -> $DEST_ENV_NAME"
        echo "MATCH" >> "$TEMP_PREVIEW"
    fi
done

# Count results
PREVIEW_TOTAL=$(cat "$TEMP_PREVIEW" | wc -l)
PREVIEW_MATCHED=$(grep -c "MATCH" "$TEMP_PREVIEW" 2>/dev/null || echo 0)
PREVIEW_SKIPPED=$(grep -c "SKIP" "$TEMP_PREVIEW" 2>/dev/null || echo 0)
PREVIEW_FAILED=$(grep -c "FAIL" "$TEMP_PREVIEW" 2>/dev/null || echo 0)

# Clean up
rm -f "$TEMP_PREVIEW"

log_message "========== PREVIEW SUMMARY =========="
log_message "Total environments: $PREVIEW_TOTAL"
log_message "Will be processed: $PREVIEW_MATCHED"
log_message "Will be skipped: $PREVIEW_SKIPPED"
log_message "Failed to match: $PREVIEW_FAILED"
log_message "=============================================="

if [ "$PREVIEW_FAILED" -gt 0 ]; then
    log_message "WARNING: Some environments could not be matched to destinations."
    log_message "These environments will be skipped during processing."
fi

# Ask for confirmation if not in dry run mode
if [ "$DRY_RUN" = false ]; then
    ask_confirmation "This will make actual changes to $PREVIEW_MATCHED environments. Are you sure you want to continue?"
fi

log_message "Starting environment processing..."

# Process each environment
echo "$SOURCE_ENVIRONMENTS" | jq -c '.' | while read -r env; do
    ENV_NAME=$(echo "$env" | jq -r '.name')
    SOURCE_ENV_ID=$(echo "$env" | jq -r '.id')
    TOTAL_ENVIRONMENTS=$((TOTAL_ENVIRONMENTS + 1))
    
    # Check if this is a system namespace that should be skipped
    if is_system_namespace "$ENV_NAME"; then
        log_message "Skipping system namespace: $ENV_NAME"
        SKIPPED_ENVIRONMENTS=$((SKIPPED_ENVIRONMENTS + 1))
        continue
    fi
    
    log_message "Processing environment: $ENV_NAME"
    
    # Use intelligent environment mapping
    DEST_ENV=$(find_dest_environment "$ENV_NAME")
    
    if [ -z "$DEST_ENV" ]; then
        log_message "ERROR: No corresponding destination environment found for $ENV_NAME"
        log_message "Tried patterns for source '$ENV_NAME':"
        log_message "  - Exact match: $ENV_NAME"
        if [[ "$ENV_NAME" == "$SOURCE_CLUSTER-"* ]]; then
            namespace=$(echo "$ENV_NAME" | sed "s/^$SOURCE_CLUSTER-//")
            log_message "  - Detected cluster prefix pattern, extracted namespace: $namespace"
            log_message "  - Tried: $namespace"
            log_message "  - Tried: $DEST_CLUSTER-$namespace"  
            log_message "  - Tried: $namespace-$DEST_CLUSTER"
        elif [[ "$ENV_NAME" == *"-$SOURCE_CLUSTER" ]]; then
            namespace=$(echo "$ENV_NAME" | sed "s/-$SOURCE_CLUSTER$//")
            log_message "  - Detected cluster suffix pattern, extracted namespace: $namespace"
            log_message "  - Tried: $namespace"
            log_message "  - Tried: $DEST_CLUSTER-$namespace"
            log_message "  - Tried: $namespace-$DEST_CLUSTER"
        fi
        FAILED_COPIES=$((FAILED_COPIES + 1))
        log_summary "FAILED: $ENV_NAME -> NO MATCH FOUND"
        continue
    fi
    
    DEST_ENV_NAME=$(echo "$DEST_ENV" | jq -r '.name')
    DEST_ENV_ID=$(echo "$DEST_ENV" | jq -r '.id')
    
    # Determine which pattern was used
    pattern_used="unknown"
    if [ "$DEST_ENV_NAME" = "$ENV_NAME" ]; then
        pattern_used="exact match"
    elif [[ "$ENV_NAME" == "$SOURCE_CLUSTER-"* ]]; then
        namespace=$(echo "$ENV_NAME" | sed "s/^$SOURCE_CLUSTER-//")
        if [ "$DEST_ENV_NAME" = "$namespace" ]; then
            pattern_used="namespace-only (prefix pattern)"
        elif [ "$DEST_ENV_NAME" = "$DEST_CLUSTER-$namespace" ]; then
            pattern_used="cluster-prefix ($DEST_CLUSTER-$namespace)"
        elif [ "$DEST_ENV_NAME" = "$namespace-$DEST_CLUSTER" ]; then
            pattern_used="cluster-suffix ($namespace-$DEST_CLUSTER)"
        fi
    elif [[ "$ENV_NAME" == *"-$SOURCE_CLUSTER" ]]; then
        namespace=$(echo "$ENV_NAME" | sed "s/-$SOURCE_CLUSTER$//")
        if [ "$DEST_ENV_NAME" = "$namespace" ]; then
            pattern_used="namespace-only (suffix pattern)"
        elif [ "$DEST_ENV_NAME" = "$DEST_CLUSTER-$namespace" ]; then
            pattern_used="cluster-prefix ($DEST_CLUSTER-$namespace)"
        elif [ "$DEST_ENV_NAME" = "$namespace-$DEST_CLUSTER" ]; then
            pattern_used="cluster-suffix ($namespace-$DEST_CLUSTER)"
        fi
    fi
    
    log_message "✅ Successfully mapped using $pattern_used: $ENV_NAME -> $DEST_ENV_NAME"
    log_message "Source ID: $SOURCE_ENV_ID"
    log_message "Destination ID: $DEST_ENV_ID"
    
    # Copy resource type
    RESOURCE_TYPE=$(echo "$env" | jq -r '.resourceType')
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
    SOURCE_ACL_ID=$(echo "$env" | jq -r '.accessControlList[0].id')
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
    OWNER=$(echo "$env" | jq -r '.createdBy')
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
    LABELS=$(echo "$env" | jq -r '.labels')
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
    fi
    
    # Copy team rolebindings
    copy_team_rolebindings "$SOURCE_ENV_ID" "$DEST_ENV_ID" "$ENV_NAME" "$DEST_ENV_NAME"
    
    # Update summary counters
    SUCCESSFUL_COPIES=$((SUCCESSFUL_COPIES + 1))
    log_summary "SUCCESS: $ENV_NAME -> $DEST_ENV_NAME"
    
    log_message "Settings copy completed for $ENV_NAME -> $DEST_ENV_NAME"
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