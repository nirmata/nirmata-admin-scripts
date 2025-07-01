#!/bin/bash

# Automated Test Suite for User Migration Script
# This script runs critical test cases and validates results

set -e

# Test configuration
SOURCE_API="https://staging.nirmata.co"
SOURCE_TOKEN="c7/tRvOi3shNloGDjtWABf/KKckLjeNNf7q1N81uTrAMA7YXxuJ43prRuQYjR4RRFssLshsT39SxvlWIeRKNIg=="
SOURCE_CLUSTER="conformance-132"
DEST_API="https://pe420.nirmata.co"
DEST_TOKEN="W6mdT3taq2nkLxmmJFyHfpMzrUeow0HTeQQx3/n7lvXfJYyT7l+Rd3oaSwR7NJyyRhnOQWF7nH1aNHYsEJURZg=="
DEST_CLUSTER="old-app-migration"

# Test results
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to run a test
run_test() {
    local test_id=$1
    local test_name=$2
    local test_command=$3
    local expected_pattern=$4
    
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
            echo -e "${RED}❌ FAILED${NC}: Expected pattern '$expected_pattern' not found"
            echo "Output: $output"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    else
        echo -e "${RED}❌ FAILED${NC}: Command execution failed"
        echo "Error: $output"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

echo "=============================================="
echo "🧪 USER MIGRATION SCRIPT TEST SUITE"
echo "=============================================="
echo "Source: $SOURCE_API ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API ($DEST_CLUSTER)"
echo ""

# Test 1: Role Preservation Check
echo "📋 CATEGORY 1: ROLE PRESERVATION TESTS"
run_test "TC-R01" "Source devops role preservation" \
    "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/users/api/users' | jq '.[] | select(.email == \"megha@nirmata.com\") | .role'" \
    "devops"

# Test 2: Identity Provider Compatibility Check
echo -e "\n📋 CATEGORY 2: IDENTITY PROVIDER TESTS"
run_test "TC-I01" "Source identity provider detection" \
    "curl -s -H 'Authorization: NIRMATA-API $SOURCE_TOKEN' '$SOURCE_API/users/api/users' | jq '[.[] | .identityProvider] | unique'" \
    "SAML"

run_test "TC-I02" "Destination identity provider detection" \
    "curl -s -H 'Authorization: NIRMATA-API $DEST_TOKEN' '$DEST_API/users/api/users' | jq '[.[] | .identityProvider] | unique'" \
    "Local"

# Test 3: Error Handling Tests
echo -e "\n📋 CATEGORY 3: ERROR HANDLING TESTS"
run_test "TC-E01" "Invalid source token handling" \
    "../phase2-users-teams/copy_cluster_teams_with_full_user_roles.sh '$SOURCE_API' 'INVALID_TOKEN' '$SOURCE_CLUSTER' '$DEST_API' '$DEST_TOKEN' '$DEST_CLUSTER' 2>&1 | head -10" \
    "Cannot index string"

run_test "TC-E03" "Non-existent source cluster handling" \
    "../phase2-users-teams/copy_cluster_teams_with_full_user_roles.sh '$SOURCE_API' '$SOURCE_TOKEN' 'NON_EXISTENT' '$DEST_API' '$DEST_TOKEN' '$DEST_CLUSTER' 2>&1 | head -10" \
    "ERROR: Source cluster 'NON_EXISTENT' not found"

# Test 4: Configuration Mode Tests
echo -e "\n📋 CATEGORY 4: CONFIGURATION MODE TESTS"
run_test "TC-C01" "Identity provider mode preserve" \
    "IDENTITY_PROVIDER_MODE=preserve ../phase2-users-teams/copy_cluster_teams_with_full_user_roles.sh '$SOURCE_API' '$SOURCE_TOKEN' '$SOURCE_CLUSTER' '$DEST_API' '$DEST_TOKEN' '$DEST_CLUSTER' 2>&1 | head -20" \
    "CRITICAL WARNING.*SAML users"

# Test 5: User Profile Validation
echo -e "\n📋 CATEGORY 5: USER PROFILE VALIDATION"
run_test "TC-U01" "Charles Edouard role validation in destination" \
    "curl -s -H 'Authorization: NIRMATA-API $DEST_TOKEN' '$DEST_API/users/api/users' | jq '.[] | select(.email == \"charles.edouard@nirmata.com\") | .role'" \
    "devops"

run_test "TC-U02" "Megha role validation in destination" \
    "curl -s -H 'Authorization: NIRMATA-API $DEST_TOKEN' '$DEST_API/users/api/users' | jq '.[] | select(.email == \"megha@nirmata.com\") | .role'" \
    "devops"

# Test 6: Team Association Validation
echo -e "\n📋 CATEGORY 6: TEAM ASSOCIATION TESTS"
run_test "TC-T01" "Team creation validation" \
    "curl -s -H 'Authorization: NIRMATA-API $DEST_TOKEN' '$DEST_API/users/api/teams' | jq '.[] | select(.name == \"new-migration-team\") | .name'" \
    "new-migration-team"

# Test 7: Script Parameter Validation
echo -e "\n📋 CATEGORY 7: PARAMETER VALIDATION TESTS"
run_test "TC-P01" "Missing parameters handling" \
    "../phase2-users-teams/copy_cluster_teams_with_full_user_roles.sh 2>&1 || true" \
    "Usage:"

# Final Results
echo ""
echo "=============================================="
echo "🏁 TEST SUITE RESULTS"
echo "=============================================="
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILED_TESTS TESTS FAILED${NC}"
    echo "Please review failed tests and fix issues before deployment."
    exit 1
fi 