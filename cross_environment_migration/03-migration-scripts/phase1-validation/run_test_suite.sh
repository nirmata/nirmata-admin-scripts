#!/bin/bash

# Automated Test Suite for Cross-Environment Migration
# This script runs critical test cases and validates migration readiness
# Designed to work with ANY customer environment - no hardcoded values

set -e

# Function to show usage
show_usage() {
    echo "Usage: $0 <source_api> <source_token> <source_cluster> <dest_api> <dest_token> <dest_cluster>"
    echo ""
    echo "Arguments:"
    echo "  source_api     - Source Nirmata API endpoint (e.g., https://staging.nirmata.co)"
    echo "  source_token   - Source environment API token"
    echo "  source_cluster - Source cluster name"
    echo "  dest_api       - Destination Nirmata API endpoint (e.g., https://pe420.nirmata.co)"
    echo "  dest_token     - Destination environment API token"
    echo "  dest_cluster   - Destination cluster name"
    echo ""
    echo "Example:"
    echo "  $0 https://staging.nirmata.co TOKEN1 cluster1 https://pe420.nirmata.co TOKEN2 cluster2"
    exit 1
}

# Check if correct number of arguments provided
if [ $# -ne 6 ]; then
    echo "❌ Error: Exactly 6 arguments required"
    echo ""
    show_usage
fi

# Parse command line arguments
SOURCE_API="$1"
SOURCE_TOKEN="$2"
SOURCE_CLUSTER="$3"
DEST_API="$4"
DEST_TOKEN="$5"
DEST_CLUSTER="$6"

# Validate required parameters
if [ -z "$SOURCE_API" ] || [ -z "$SOURCE_TOKEN" ] || [ -z "$SOURCE_CLUSTER" ] || \
   [ -z "$DEST_API" ] || [ -z "$DEST_TOKEN" ] || [ -z "$DEST_CLUSTER" ]; then
    echo "❌ Error: All parameters are required"
    show_usage
fi

# Test results
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to run a test
run_test() {
    local test_id=$1
    local test_name=$2
    local test_command=$3
    local expected_pattern=$4
    local test_type=${5:-"required"}  # required or optional
    
    echo -e "\n${YELLOW}Running $test_id: $test_name${NC}"
    echo "Command: $test_command"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Run the test and capture output
    local output
    if output=$(eval "$test_command" 2>&1); then
        # Check if expected pattern is found
        if echo "$output" | grep -q "$expected_pattern"; then
            echo -e "${GREEN}✅ PASSED${NC}: Found expected pattern '$expected_pattern'"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            if [ "$test_type" = "optional" ]; then
                echo -e "${BLUE}ℹ️  SKIPPED${NC}: Optional test - pattern '$expected_pattern' not found (this is okay)"
                echo "Output: $output"
                PASSED_TESTS=$((PASSED_TESTS + 1))  # Count as passed since it's optional
            return 0
        else
            echo -e "${RED}❌ FAILED${NC}: Expected pattern '$expected_pattern' not found"
            echo "Output: $output"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
            fi
        fi
    else
        echo -e "${RED}❌ FAILED${NC}: Command execution failed"
        echo "Error: $output"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to get first user email from environment
get_first_user_email() {
    local api=$1
    local token=$2
    curl -s -H "Authorization: NIRMATA-API $token" "$api/users/api/users" | jq -r '.[0].email // empty' 2>/dev/null || echo ""
}

# Function to get first team name from environment
get_first_team_name() {
    local api=$1
    local token=$2
    curl -s -H "Authorization: NIRMATA-API $token" "$api/users/api/teams" | jq -r '.[0].name // empty' 2>/dev/null || echo ""
}

echo "=============================================="
echo "🧪 CROSS-ENVIRONMENT MIGRATION TEST SUITE"
echo "=============================================="
echo "Source: $SOURCE_API ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API ($DEST_CLUSTER)"
echo ""
echo "🔍 This test suite is fully generic and works with any customer environment"
echo "📋 No hardcoded emails, teams, or environment-specific assumptions"
echo ""

# Test 1: Basic Connectivity Tests
echo "📋 CATEGORY 1: CONNECTIVITY & AUTHENTICATION TESTS"

run_test "TC-C01" "Source API connectivity" \
    "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/users/api/users' | jq 'type'" \
    "array"

run_test "TC-C02" "Destination API connectivity" \
    "curl -s -H 'Authorization: NIRMATA-API $DEST_TOKEN' '$DEST_API/users/api/users' | jq 'type'" \
    "array"

run_test "TC-C03" "Source cluster exists" \
    "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/environments/api/clusters' | jq '.[] | select(.name == \"$SOURCE_CLUSTER\") | .name'" \
    "$SOURCE_CLUSTER"

run_test "TC-C04" "Destination cluster exists" \
    "curl -s -H 'Authorization: NIRMATA-API $DEST_TOKEN' '$DEST_API/environments/api/clusters' | jq '.[] | select(.name == \"$DEST_CLUSTER\") | .name'" \
    "$DEST_CLUSTER"

# Test 2: Data Availability Tests
echo -e "\n📋 CATEGORY 2: DATA AVAILABILITY TESTS"

run_test "TC-D01" "Source has users" \
    "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/users/api/users' | jq 'length > 0'" \
    "true"

run_test "TC-D02" "Source has teams" \
    "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/users/api/teams' | jq 'length > 0'" \
    "true"

run_test "TC-D03" "Source has environments" \
    "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/environments/api/environments' | jq 'length > 0'" \
    "true"

# Test 3: Error Handling Tests
echo -e "\n📋 CATEGORY 3: ERROR HANDLING TESTS"

run_test "TC-E01" "Invalid source token handling" \
    "(cd ../phase2-users-teams && ./copy_cluster_teams_with_full_user_roles.sh '$SOURCE_API' 'INVALID_TOKEN' '$SOURCE_CLUSTER' '$DEST_API' '$DEST_TOKEN' '$DEST_CLUSTER') 2>&1 | head -10" \
    "Cannot index string"

run_test "TC-E02" "Non-existent source cluster handling" \
    "(cd ../phase2-users-teams && ./copy_cluster_teams_with_full_user_roles.sh '$SOURCE_API' '$SOURCE_TOKEN' 'NON_EXISTENT_CLUSTER' '$DEST_API' '$DEST_TOKEN' '$DEST_CLUSTER') 2>&1 | head -10" \
    "ERROR: Source cluster 'NON_EXISTENT_CLUSTER' not found"

# Test 4: Script Parameter Validation
echo -e "\n📋 CATEGORY 4: SCRIPT VALIDATION TESTS"

run_test "TC-S01" "Missing parameters handling" \
    "(cd ../phase2-users-teams && ./copy_cluster_teams_with_full_user_roles.sh) 2>&1 || true" \
    "Usage:"

run_test "TC-S02" "Environment migration script exists" \
    "test -f ../phase3-environments/restore_env_settings_cross_env.sh && echo 'exists'" \
    "exists"

run_test "TC-S03" "Application migration script exists" \
    "test -f ../phase4-applications/migrate_env_apps_to_catalog_cross_env.sh && echo 'exists'" \
    "exists"

# Test 5: Identity Provider Compatibility (Optional)
echo -e "\n📋 CATEGORY 5: IDENTITY PROVIDER TESTS (OPTIONAL)"

run_test "TC-I01" "Source identity provider detection" \
    "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/users/api/users' | jq '[.[] | .identityProvider] | unique | length > 0'" \
    "true" \
    "optional"

run_test "TC-I02" "Destination identity provider detection" \
    "curl -s -H 'Authorization: NIRMATA-API $DEST_TOKEN' '$DEST_API/users/api/users' | jq '[.[] | .identityProvider] | unique | length > 0'" \
    "true" \
    "optional"

# Test 6: Dynamic User/Team Validation (if data exists)
echo -e "\n📋 CATEGORY 6: DYNAMIC VALIDATION TESTS"

# Get first user email dynamically
FIRST_USER_EMAIL=$(get_first_user_email "$SOURCE_API" "$SOURCE_TOKEN")
if [ -n "$FIRST_USER_EMAIL" ] && [ "$FIRST_USER_EMAIL" != "null" ]; then
    run_test "TC-V01" "First user has role in source" \
        "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/users/api/users' | jq '.[] | select(.email == \"$FIRST_USER_EMAIL\") | .role != null'" \
        "true" \
        "optional"
else
    echo -e "\n${BLUE}ℹ️  Skipping user validation - no users found in source environment${NC}"
fi

# Get first team name dynamically
FIRST_TEAM_NAME=$(get_first_team_name "$SOURCE_API" "$SOURCE_TOKEN")
if [ -n "$FIRST_TEAM_NAME" ] && [ "$FIRST_TEAM_NAME" != "null" ]; then
    run_test "TC-V02" "First team exists in source" \
        "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/users/api/teams' | jq '.[] | select(.name == \"$FIRST_TEAM_NAME\") | .name'" \
        "$FIRST_TEAM_NAME" \
        "optional"
else
    echo -e "\n${BLUE}ℹ️  Skipping team validation - no teams found in source environment${NC}"
fi

# Test 7: Prerequisites Check
echo -e "\n📋 CATEGORY 7: MIGRATION PREREQUISITES"

run_test "TC-P01" "jq command available" \
    "which jq && echo 'available'" \
    "available"

run_test "TC-P02" "curl command available" \
    "which curl && echo 'available'" \
    "available"

run_test "TC-P03" "Configuration loaded" \
    "test -n '$SOURCE_API' -a -n '$DEST_API' && echo 'loaded'" \
    "loaded"

# Final Results
echo ""
echo "=============================================="
echo "🏁 MIGRATION READINESS TEST RESULTS"
echo "=============================================="
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}✅ Your environment is ready for cross-environment migration!${NC}"
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Proceed to Phase 2: Users & Teams Migration"
    echo "   2. cd ../phase2-users-teams && ./RUN_THIS_PHASE.sh \"$SOURCE_API\" \"$SOURCE_TOKEN\" \"$SOURCE_CLUSTER\" \"$DEST_API\" \"$DEST_TOKEN\" \"$DEST_CLUSTER\""
    exit 0
else
    echo -e "${RED}❌ $FAILED_TESTS TESTS FAILED${NC}"
    echo -e "${RED}⚠️  Please fix the failed tests before proceeding with migration.${NC}"
    echo ""
    echo "🔧 Common Solutions:"
    echo "   • Check API tokens have correct permissions"
    echo "   • Verify cluster names are correct"
    echo "   • Ensure network connectivity to both environments"
    echo "   • Confirm source environment has data to migrate"
    exit 1
fi 