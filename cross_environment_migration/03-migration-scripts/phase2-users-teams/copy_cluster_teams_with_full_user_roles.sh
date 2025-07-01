#!/bin/bash

# Copy Teams and Users with Complete Roles/Permissions Profile
# This script extracts users with their full permission profile and recreates them properly

set -e

# Identity Provider Migration Configuration
# Set IDENTITY_PROVIDER_MODE environment variable to control behavior:
# - "preserve" (default): Try to preserve source identity providers, warn if not supported
# - "convert": Force convert all users to Local identity provider
IDENTITY_PROVIDER_MODE="${IDENTITY_PROVIDER_MODE:-preserve}"

# Check if all required parameters are provided
if [ $# -ne 6 ]; then
    echo "Usage: $0 <source_api_endpoint> <source_token> <source_cluster> <dest_api_endpoint> <dest_token> <dest_cluster>"
    echo ""
    echo "Example:"
    echo "$0 https://source.nirmata.co SOURCE_TOKEN source-cluster https://destination.nirmata.co DEST_TOKEN dest-cluster"
    exit 1
fi

# Configuration from parameters
SOURCE_API_ENDPOINT=$1
SOURCE_TOKEN=$2
SOURCE_CLUSTER=$3
DEST_API_ENDPOINT=$4
DEST_TOKEN=$5
DEST_CLUSTER=$6

# Create logs directory
mkdir -p logs
LOG_FILE="logs/full_user_migration_$(date +%Y%m%d_%H%M%S).log"
SUMMARY_FILE="logs/full_user_migration_summary_$(date +%Y%m%d_%H%M%S).log"

echo "=============================================================="
echo "Complete User Profile Migration with Roles & Permissions"
echo "=============================================================="
echo "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER)"
echo "Log file: $LOG_FILE"
echo ""

# Function to log messages
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

# Function to log summary
log_summary() {
    echo "$1" >> "$SUMMARY_FILE"
}

# Initialize counters
TOTAL_USERS=0
SUCCESSFUL_USERS=0
FAILED_USERS=0
TOTAL_TEAMS=0
SUCCESSFUL_TEAMS=0
FAILED_TEAMS=0

log_message "Starting complete user profile migration..."

# Get source and destination cluster IDs
log_message "Getting cluster IDs..."
SOURCE_CLUSTER_ID=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
    "$SOURCE_API_ENDPOINT/environments/api/clusters" | \
    jq -r ".[] | select(.name == \"$SOURCE_CLUSTER\") | .id")

DEST_CLUSTER_ID=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
    "$DEST_API_ENDPOINT/environments/api/clusters" | \
    jq -r ".[] | select(.name == \"$DEST_CLUSTER\") | .id")

if [ -z "$SOURCE_CLUSTER_ID" ] || [ "$SOURCE_CLUSTER_ID" = "null" ]; then
    log_message "ERROR: Source cluster '$SOURCE_CLUSTER' not found"
    exit 1
fi

if [ -z "$DEST_CLUSTER_ID" ] || [ "$DEST_CLUSTER_ID" = "null" ]; then
    log_message "ERROR: Destination cluster '$DEST_CLUSTER' not found"
    exit 1
fi

log_message "Source cluster ID: $SOURCE_CLUSTER_ID"
log_message "Destination cluster ID: $DEST_CLUSTER_ID"

# Get all data from source
log_message "Fetching source data..."
SOURCE_TEAMS=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/users/api/teams")
SOURCE_USERS=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/users/api/users")
SOURCE_ROLES=$(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API_ENDPOINT/users/api/roles")

# Get all data from destination
log_message "Fetching destination data..."
DEST_TEAMS=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/users/api/teams")
DEST_USERS=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/users/api/users")
DEST_ROLES=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/users/api/roles")

# Check identity provider compatibility
check_identity_provider_compatibility() {
    log_message "Checking identity provider compatibility..."
    
    local source_identity_providers=$(echo "$SOURCE_USERS" | jq -r '[.[] | .identityProvider] | unique | .[]' 2>/dev/null)
    local dest_identity_providers=$(echo "$DEST_USERS" | jq -r '[.[] | .identityProvider] | unique | .[]' 2>/dev/null)
    
    log_message "Source identity providers: $(echo "$source_identity_providers" | tr '\n' ', ' | sed 's/,$//')"
    log_message "Destination identity providers: $(echo "$dest_identity_providers" | tr '\n' ', ' | sed 's/,$//')"
    
    local saml_users_count=$(echo "$SOURCE_USERS" | jq '[.[] | select(.identityProvider == "SAML")] | length' 2>/dev/null || echo "0")
    local azure_users_count=$(echo "$SOURCE_USERS" | jq '[.[] | select(.identityProvider == "Azure AD")] | length' 2>/dev/null || echo "0")
    
    if [ "$saml_users_count" -gt 0 ] || [ "$azure_users_count" -gt 0 ]; then
        if ! echo "$dest_identity_providers" | grep -q "SAML\|Azure"; then
            log_message "🚨 CRITICAL WARNING: Source has $saml_users_count SAML users and $azure_users_count Azure AD users"
            log_message "🚨 But destination only supports: $(echo "$dest_identity_providers" | tr '\n' ', ' | sed 's/,$//')"
            log_message "🚨 These users will be converted to Local and lose SSO access!"
            log_message "🚨 RECOMMENDATION: Configure SAML/Azure AD in destination BEFORE running migration"
            log_message "🚨 Contact Nirmata support to enable SSO in destination environment"
        fi
    fi
}

check_identity_provider_compatibility

# Function to create user with complete profile in destination
create_user_with_full_profile() {
    local user_id=$1
    local user_email=$2
    local user_name=$3
    
    log_message "Creating user with full profile: $user_email"
    
    # Check if user already exists in destination
    local dest_user_id=$(echo "$DEST_USERS" | jq -r --arg email "$user_email" '.[] | select(.email == $email) | .id')
    
    if [ ! -z "$dest_user_id" ] && [ "$dest_user_id" != "null" ]; then
        log_message "User '$user_email' already exists in destination (ID: $dest_user_id)"
        
        # Get user's source roles to merge with existing destination roles
        local user_data=$(echo "$SOURCE_USERS" | jq -r --arg id "$user_id" '.[] | select(.id == $id)')
        local source_roles=$(echo "$user_data" | jq -r '.roles[]?.name // empty')
        local source_role=$(echo "$user_data" | jq -r '.role // "devops"')
        
        log_message "🔄 MERGE MODE: Updating existing user roles for $user_email"
        log_message "Source role: $source_role, Additional roles: $source_roles"
        
        # Merge roles for existing user (additive approach)
        if [ ! -z "$source_roles" ] || [ ! -z "$source_role" ]; then
            merge_user_roles "$dest_user_id" "$user_email" "$source_role" "$source_roles"
        fi
        
        return 0
    fi
    
    # Get user's complete profile from source
    local user_data=$(echo "$SOURCE_USERS" | jq -r --arg id "$user_id" '.[] | select(.id == $id)')
    local user_roles=$(echo "$user_data" | jq -r '.roles[]?.name // empty')
    local source_role=$(echo "$user_data" | jq -r '.role // "devops"')
    local source_identity_provider=$(echo "$user_data" | jq -r '.identityProvider // "Local"')
    
    log_message "User $user_email has source role: $source_role, identity provider: $source_identity_provider"
    
    # Try different user creation methods
    
    # Method 1: Create user with tenant context
    log_message "Attempting tenant-based user creation for: $user_email"
    
    # Get tenant ID from destination
    local dest_tenant_id=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
        "$DEST_API_ENDPOINT/users/api/tenants" | jq -r '.[0].id')
    
    if [ ! -z "$dest_tenant_id" ] && [ "$dest_tenant_id" != "null" ]; then
        # Use the actual source role and determine identity provider based on mode
        local user_role="$source_role"
        local identity_provider="$source_identity_provider"
        
        if [ "$IDENTITY_PROVIDER_MODE" = "convert" ]; then
            log_message "🔄 IDENTITY_PROVIDER_MODE=convert: Converting '$source_identity_provider' to 'Local' for $user_email"
            identity_provider="Local"
        else
            # preserve mode - check if destination supports the source identity provider
            local dest_identity_providers=$(echo "$DEST_USERS" | jq -r '[.[] | .identityProvider] | unique | .[]' 2>/dev/null || echo "Local")
            
            if ! echo "$dest_identity_providers" | grep -q "^$source_identity_provider$"; then
                log_message "⚠️  WARNING: Destination does not support identity provider '$source_identity_provider'"
                log_message "⚠️  Available identity providers in destination: $(echo "$dest_identity_providers" | tr '\n' ', ' | sed 's/,$//')"
                log_message "⚠️  RECOMMENDATION: Configure SAML/Azure AD in destination before migration"
                log_message "⚠️  For now, converting '$source_identity_provider' to 'Local' for $user_email"
                log_message "⚠️  This user will need to reset password and may lose SSO access!"
                log_message "⚠️  To force preserve identity providers, set IDENTITY_PROVIDER_MODE=preserve and configure SSO first"
                identity_provider="Local"
            else
                log_message "✅ Identity provider '$source_identity_provider' is supported in destination"
            fi
        fi
        
        local tenant_payload="{
            \"email\": \"$user_email\",
            \"name\": \"$user_name\",
            \"role\": \"$user_role\",
            \"identityProvider\": \"$identity_provider\",
            \"parent\": {
                \"id\": \"$dest_tenant_id\",
                \"service\": \"Users\",
                \"modelIndex\": \"Tenant\",
                \"childRelation\": \"users\"
            }
        }"
        
        log_message "Creating user with role: $user_role"
        
        local tenant_response=$(curl -s -X POST \
            -H "Authorization: NIRMATA-API $DEST_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$tenant_payload" \
            "$DEST_API_ENDPOINT/users/api/tenants/$dest_tenant_id/users")
        
        local tenant_user_id=$(echo "$tenant_response" | jq -r '.id // empty')
        
        if [ ! -z "$tenant_user_id" ] && [ "$tenant_user_id" != "null" ]; then
            log_message "✅ Tenant-based user creation successful for $user_email (ID: $tenant_user_id)"
            
            # Assign roles to the created user
            if [ ! -z "$user_roles" ]; then
                assign_user_roles "$tenant_user_id" "$user_email" "$user_roles"
            fi
            
            return 0
        else
            log_message "Tenant-based creation failed: $tenant_response"
        fi
    fi
    
    # Method 2: Direct user creation
    log_message "Attempting direct user creation for: $user_email"
    local basic_payload="{\"email\": \"$user_email\", \"name\": \"$user_name\"}"
    local response=$(curl -s -X POST \
        -H "Authorization: NIRMATA-API $DEST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$basic_payload" \
        "$DEST_API_ENDPOINT/users/api/users")
    
    local new_user_id=$(echo "$response" | jq -r '.id // empty')
    
    if [ ! -z "$new_user_id" ] && [ "$new_user_id" != "null" ]; then
        log_message "✅ Direct user creation successful for $user_email (ID: $new_user_id)"
        
        # Assign roles to the created user
        if [ ! -z "$user_roles" ]; then
            assign_user_roles "$new_user_id" "$user_email" "$user_roles"
        fi
        
        return 0
    else
        log_message "❌ Failed to create user '$user_email': $response"
        return 1
    fi
}

# Function to merge roles for existing users (additive approach)
merge_user_roles() {
    local user_id=$1
    local user_email=$2
    local source_primary_role=$3
    local source_additional_roles=$4
    
    log_message "🔄 Merging roles for existing user: $user_email"
    
    # Get current user roles from destination
    local current_user_data=$(echo "$DEST_USERS" | jq -r --arg id "$user_id" '.[] | select(.id == $id)')
    local current_primary_role=$(echo "$current_user_data" | jq -r '.role // ""')
    local current_additional_roles=$(echo "$current_user_data" | jq -r '.roles[]?.name // empty')
    
    log_message "Current destination roles - Primary: $current_primary_role, Additional: $current_additional_roles"
    log_message "Source roles to merge - Primary: $source_primary_role, Additional: $source_additional_roles"
    
    # Build comprehensive roles list (avoid duplicates)
    local all_roles=""
    
    # Add current primary role if it exists
    if [ ! -z "$current_primary_role" ] && [ "$current_primary_role" != "null" ]; then
        all_roles="$current_primary_role"
    fi
    
    # Add source primary role if different from current
    if [ ! -z "$source_primary_role" ] && [ "$source_primary_role" != "$current_primary_role" ]; then
        if [ -z "$all_roles" ]; then
            all_roles="$source_primary_role"
        else
            all_roles="$all_roles $source_primary_role"
        fi
    fi
    
    # Add current additional roles
    for role in $current_additional_roles; do
        if [ ! -z "$role" ] && ! echo "$all_roles" | grep -q "\b$role\b"; then
            all_roles="$all_roles $role"
        fi
    done
    
    # Add source additional roles
    for role in $source_additional_roles; do
        if [ ! -z "$role" ] && ! echo "$all_roles" | grep -q "\b$role\b"; then
            all_roles="$all_roles $role"
        fi
    done
    
    # Build roles array for API call
    local dest_role_ids=""
    for role_name in $all_roles; do
        # Handle both object and string role formats
        local dest_role_id=$(echo "$DEST_ROLES" | jq -r --arg name "$role_name" '
            if type == "array" then
                .[] | if type == "object" then 
                    select(.name == $name) | .id 
                else 
                    if . == $name then . else empty end 
                end
            else
                empty
            end')
        
        if [ ! -z "$dest_role_id" ] && [ "$dest_role_id" != "null" ]; then
            if [ -z "$dest_role_ids" ]; then
                dest_role_ids="\"$dest_role_id\""
            else
                dest_role_ids="$dest_role_ids, \"$dest_role_id\""
            fi
            log_message "✅ Including role '$role_name' (ID: $dest_role_id)"
        else
            log_message "⚠️  Role '$role_name' not found in destination - skipping"
        fi
    done
    
    # Update user with merged roles
    if [ ! -z "$dest_role_ids" ]; then
        local role_payload="{\"roles\": [$dest_role_ids]}"
        local role_response=$(curl -s -X PUT \
            -H "Authorization: NIRMATA-API $DEST_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$role_payload" \
            "$DEST_API_ENDPOINT/users/api/users/$user_id")
        
        if echo "$role_response" | jq -e '.id' > /dev/null 2>&1; then
            log_message "✅ Merged roles updated for $user_email successfully"
            log_message "Final roles: $(echo "$all_roles" | tr ' ' ',')"
        else
            log_message "❌ Failed to update merged roles for $user_email: $role_response"
        fi
    else
        log_message "⚠️  No valid roles found to assign to $user_email"
    fi
}

# Function to assign roles to user
assign_user_roles() {
    local user_id=$1
    local user_email=$2
    local user_roles=$3
    
    log_message "Assigning roles to user: $user_email"
    
    # Build roles array for destination
    local dest_role_ids=""
    for role_name in $user_roles; do
        local dest_role_id=$(echo "$DEST_ROLES" | jq -r --arg name "$role_name" '.[] | select(.name == $name) | .id')
        
        if [ ! -z "$dest_role_id" ] && [ "$dest_role_id" != "null" ]; then
            if [ -z "$dest_role_ids" ]; then
                dest_role_ids="\"$dest_role_id\""
            else
                dest_role_ids="$dest_role_ids, \"$dest_role_id\""
            fi
            log_message "Mapped role '$role_name' to ID: $dest_role_id"
        else
            log_message "⚠️  Role '$role_name' not found in destination"
        fi
    done
    
    if [ ! -z "$dest_role_ids" ]; then
        local role_payload="{\"roles\": [$dest_role_ids]}"
        local role_response=$(curl -s -X PUT \
            -H "Authorization: NIRMATA-API $DEST_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$role_payload" \
            "$DEST_API_ENDPOINT/users/api/users/$user_id")
        
        if echo "$role_response" | jq -e '.id' > /dev/null 2>&1; then
            log_message "✅ Roles assigned to $user_email successfully"
        else
            log_message "❌ Failed to assign roles to $user_email: $role_response"
        fi
    else
        log_message "⚠️  No valid roles found to assign to $user_email"
    fi
}

# Extract and create all unique users with their profiles
log_message "Extracting all unique users from teams..."

# Create temporary file to track processed users
temp_processed_users=$(mktemp)

while read -r team_data; do
    if [ -n "$team_data" ]; then
        team_name=$(echo "$team_data" | jq -r '.name')
        team_users=$(echo "$team_data" | jq -r '.users[]?.id // empty')
        
        log_message "Processing users from team: $team_name"
        
        for user_id in $team_users; do
            # Check if user already processed
            if ! grep -q "^$user_id$" "$temp_processed_users" 2>/dev/null; then
                echo "$user_id" >> "$temp_processed_users"
                
                user_data=$(echo "$SOURCE_USERS" | jq -r --arg id "$user_id" '.[] | select(.id == $id)')
                user_email=$(echo "$user_data" | jq -r '.email')
                user_name=$(echo "$user_data" | jq -r '.name // .email')
                
                if [ ! -z "$user_email" ] && [ "$user_email" != "null" ]; then
                    TOTAL_USERS=$((TOTAL_USERS + 1))
                    
                    if create_user_with_full_profile "$user_id" "$user_email" "$user_name"; then
                        SUCCESSFUL_USERS=$((SUCCESSFUL_USERS + 1))
                    else
                        FAILED_USERS=$((FAILED_USERS + 1))
                    fi
                fi
            fi
        done
    fi
done < <(echo "$SOURCE_TEAMS" | jq -c '.[]')

# Clean up temp file
rm -f "$temp_processed_users"

# Refresh destination users list after creating new ones
log_message "Refreshing destination user list..."
DEST_USERS=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API_ENDPOINT/users/api/users")

# Now create/update teams and associate users
log_message "Creating teams and associating users..."
while read -r team_data; do
    if [ -n "$team_data" ]; then
        TOTAL_TEAMS=$((TOTAL_TEAMS + 1))
        
        team_name=$(echo "$team_data" | jq -r '.name')
        team_description=$(echo "$team_data" | jq -r '.description // ""')
        team_users=$(echo "$team_data" | jq -r '.users[]?.id // empty')
        
        log_message "Processing team: $team_name"
        
        # Check if team exists in destination
        dest_team_id=$(echo "$DEST_TEAMS" | jq -r --arg name "$team_name" '.[] | select(.name == $name) | .id')
        
        if [ -z "$dest_team_id" ] || [ "$dest_team_id" = "null" ]; then
            # Create team
            team_payload="{\"name\": \"$team_name\", \"description\": \"$team_description\"}"
            team_response=$(curl -s -X POST \
                -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$team_payload" \
                "$DEST_API_ENDPOINT/users/api/teams")
            
            dest_team_id=$(echo "$team_response" | jq -r '.id')
            
            if [ ! -z "$dest_team_id" ] && [ "$dest_team_id" != "null" ]; then
                log_message "✅ Team '$team_name' created (ID: $dest_team_id)"
            else
                log_message "❌ Failed to create team '$team_name': $team_response"
                FAILED_TEAMS=$((FAILED_TEAMS + 1))
                continue
            fi
        else
            log_message "Team '$team_name' already exists (ID: $dest_team_id)"
        fi
        
        # Get existing team members (for merge approach)
        log_message "🔄 MERGE MODE: Getting existing team members for '$team_name'"
        existing_team_data=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
            "$DEST_API_ENDPOINT/users/api/teams/$dest_team_id")
        existing_member_ids=$(echo "$existing_team_data" | jq -r '.users[]?.id // empty')
        existing_count=$(echo "$existing_member_ids" | wc -w)
        
        log_message "Team '$team_name' currently has $existing_count existing members"
        
        # Build list of source users to add
        source_user_ids=""
        new_members_count=0
        
        for source_user_id in $team_users; do
            user_email=$(echo "$SOURCE_USERS" | jq -r --arg id "$source_user_id" '.[] | select(.id == $id) | .email')
            
            if [ ! -z "$user_email" ] && [ "$user_email" != "null" ]; then
                dest_user_id=$(echo "$DEST_USERS" | jq -r --arg email "$user_email" '.[] | select(.email == $email) | .id')
                
                if [ ! -z "$dest_user_id" ] && [ "$dest_user_id" != "null" ]; then
                    # Check if user is already a member (avoid duplicates)
                    if ! echo "$existing_member_ids" | grep -q "\b$dest_user_id\b"; then
                        if [ -z "$source_user_ids" ]; then
                            source_user_ids="\"$dest_user_id\""
                        else
                            source_user_ids="$source_user_ids, \"$dest_user_id\""
                        fi
                        new_members_count=$((new_members_count + 1))
                        log_message "Will add new member: $user_email (ID: $dest_user_id)"
                    else
                        log_message "User $user_email already member of team '$team_name' - skipping"
                    fi
                else
                    log_message "⚠️  User $user_email not found in destination for team association"
                fi
            fi
        done
        
        # Combine existing and new members
        all_member_ids=""
        total_members=0
        
        # Add existing members
        for member_id in $existing_member_ids; do
            if [ ! -z "$member_id" ]; then
                if [ -z "$all_member_ids" ]; then
                    all_member_ids="\"$member_id\""
                else
                    all_member_ids="$all_member_ids, \"$member_id\""
                fi
                total_members=$((total_members + 1))
            fi
        done
        
        # Add new members
        if [ ! -z "$source_user_ids" ]; then
            if [ -z "$all_member_ids" ]; then
                all_member_ids="$source_user_ids"
            else
                all_member_ids="$all_member_ids, $source_user_ids"
            fi
            total_members=$((total_members + new_members_count))
        fi
        
        # Update team with merged membership
        if [ ! -z "$all_member_ids" ]; then
            team_update_payload="{\"users\": [$all_member_ids]}"
            team_update_response=$(curl -s -X PUT \
                -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$team_update_payload" \
                "$DEST_API_ENDPOINT/users/api/teams/$dest_team_id")
            
            if echo "$team_update_response" | jq -e '.id' > /dev/null 2>&1; then
                log_message "✅ Team '$team_name' updated: $existing_count existing + $new_members_count new = $total_members total members"
                SUCCESSFUL_TEAMS=$((SUCCESSFUL_TEAMS + 1))
            else
                log_message "❌ Failed to update team '$team_name': $team_update_response"
                FAILED_TEAMS=$((FAILED_TEAMS + 1))
            fi
        else
            log_message "⚠️  No members to add to team '$team_name'"
            SUCCESSFUL_TEAMS=$((SUCCESSFUL_TEAMS + 1))
        fi
        
        source_user_count=$(echo "$team_users" | wc -w)
        log_summary "TEAM: $team_name | Source Users: $source_user_count | Associated: $associated_count"
    fi
done < <(echo "$SOURCE_TEAMS" | jq -c '.[]')

# Final summary
log_message "Complete user profile migration finished!"
log_message "Users - Total: $TOTAL_USERS, Successful: $SUCCESSFUL_USERS, Failed: $FAILED_USERS"
log_message "Teams - Total: $TOTAL_TEAMS, Successful: $SUCCESSFUL_TEAMS, Failed: $FAILED_TEAMS"

log_summary "=========================================="
log_summary "COMPLETE USER PROFILE MIGRATION SUMMARY"
log_summary "=========================================="
log_summary "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER)"
log_summary "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER)"
log_summary "Users - Total: $TOTAL_USERS, Successful: $SUCCESSFUL_USERS, Failed: $FAILED_USERS"
log_summary "Teams - Total: $TOTAL_TEAMS, Successful: $SUCCESSFUL_TEAMS, Failed: $FAILED_TEAMS"

if [ $FAILED_USERS -gt 0 ] || [ $FAILED_TEAMS -gt 0 ]; then
    log_message "⚠️  Some items failed to migrate. Check the logs for details."
    exit 1
else
    log_message "✅ Complete user profile migration successful!"
    exit 0
fi 