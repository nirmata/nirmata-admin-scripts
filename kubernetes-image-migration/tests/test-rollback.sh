#!/bin/bash

# Comprehensive Rollback Testing Script
# Tests all rollback functionality and edge cases

set -euo pipefail

# Test configuration
MIGRATION_SCRIPT="./k8s-image-migration.sh"
ROLLBACK_SCRIPT="./k8s-image-rollback.sh"
TEST_NAMESPACE="test-rollback-validation"
SOURCE_REGISTRY="docker-repo.nibr.novartis.net"
DEST_REGISTRY="ghcr.io/vikashkaushik01"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    ((TOTAL_TESTS++))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Setup test environment
setup_rollback_test() {
    log_info "Setting up rollback test environment..."
    
    # Clean up any existing test namespace
    kubectl delete namespace $TEST_NAMESPACE --ignore-not-found=true
    sleep 5
    
    # Create test namespace and resources
    cat << EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: $TEST_NAMESPACE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rollback-test-app
  namespace: $TEST_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rollback-test
  template:
    metadata:
      labels:
        app: rollback-test
    spec:
      containers:
      - name: app
        image: $SOURCE_REGISTRY/nirmata/pause:3.6
        ports:
        - containerPort: 8080
      - name: sidecar
        image: $SOURCE_REGISTRY/nirmata/nginx:1.21
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rollback-test-statefulset
  namespace: $TEST_NAMESPACE
spec:
  serviceName: rollback-test-statefulset
  replicas: 1
  selector:
    matchLabels:
      app: rollback-test-sts
  template:
    metadata:
      labels:
        app: rollback-test-sts
    spec:
      containers:
      - name: main
        image: $SOURCE_REGISTRY/nirmata/pause:3.6
        ports:
        - containerPort: 8080
EOF
    
    # Create imagePullSecret
    kubectl create secret docker-registry artifactory-secret \
        --docker-server=ghcr.io \
        --docker-username=vikashkaushik01 \
        --docker-password=YOUR_GITHUB_TOKEN \
        -n $TEST_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Wait for resources to be ready
    sleep 10
    
    log_info "Rollback test environment setup complete"
}

# Test 1: Basic rollback script functionality
test_rollback_basic_functionality() {
    log_info "=== Testing Rollback Basic Functionality ==="
    
    # Test help command
    log_test "Rollback help command works"
    if $ROLLBACK_SCRIPT --help >/dev/null 2>&1; then
        log_pass "Rollback help command works"
    else
        log_fail "Rollback help command failed"
    fi
    
    # Test missing CSV file parameter
    log_test "Missing CSV file parameter validation"
    if $ROLLBACK_SCRIPT --namespace test 2>&1 | grep -q "CSV file is required"; then
        log_pass "Missing CSV file parameter validation"
    else
        log_fail "Missing CSV file parameter validation"
    fi
    
    # Test non-existent CSV file
    log_test "Non-existent CSV file validation"
    if $ROLLBACK_SCRIPT --csv-file non-existent.csv 2>&1 | grep -q "does not exist"; then
        log_pass "Non-existent CSV file validation"
    else
        log_fail "Non-existent CSV file validation"
    fi
}

# Test 2: End-to-end migration and rollback
test_end_to_end_rollback() {
    log_info "=== Testing End-to-End Migration and Rollback ==="
    
    local migration_csv="rollback-test-migration.csv"
    local rollback_csv="rollback-test-rollback.csv"
    
    # Step 1: Record original state
    log_test "Recording original image state"
    local original_image
    original_image=$(kubectl get deployment rollback-test-app -n $TEST_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    if [[ "$original_image" == "$SOURCE_REGISTRY/nirmata/pause:3.6" ]]; then
        log_pass "Original image state recorded: $original_image"
    else
        log_fail "Unexpected original image: $original_image"
        return 1
    fi
    
    # Step 2: Perform migration
    log_test "Performing migration"
    if echo "y" | $MIGRATION_SCRIPT --namespace $TEST_NAMESPACE --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY --output-csv $migration_csv >/dev/null 2>&1; then
        log_pass "Migration completed successfully"
    else
        log_fail "Migration failed"
        return 1
    fi
    
    # Step 3: Verify migration
    log_test "Verifying migration result"
    local migrated_image
    migrated_image=$(kubectl get deployment rollback-test-app -n $TEST_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    if [[ "$migrated_image" == "$DEST_REGISTRY/nirmata/pause:3.6" ]]; then
        log_pass "Migration verified: $migrated_image"
    else
        log_fail "Migration verification failed: $migrated_image"
        return 1
    fi
    
    # Step 4: Check automatic rollback backup was created
    log_test "Checking automatic rollback backup creation"
    local rollback_backup
    rollback_backup=$(ls rollback-test-migration_rollback_*.csv 2>/dev/null | head -1)
    if [[ -n "$rollback_backup" && -f "$rollback_backup" ]]; then
        log_pass "Automatic rollback backup created: $rollback_backup"
    else
        log_fail "Automatic rollback backup not found"
        return 1
    fi
    
    # Step 5: Perform rollback using automatic backup
    log_test "Performing rollback using automatic backup"
    if echo "y" | $ROLLBACK_SCRIPT --csv-file "$rollback_backup" --rollback-csv $rollback_csv >/dev/null 2>&1; then
        log_pass "Rollback completed successfully"
    else
        log_fail "Rollback failed"
        return 1
    fi
    
    # Step 6: Verify rollback
    log_test "Verifying rollback result"
    local rolled_back_image
    rolled_back_image=$(kubectl get deployment rollback-test-app -n $TEST_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    if [[ "$rolled_back_image" == "$original_image" ]]; then
        log_pass "Rollback verified: $rolled_back_image"
    else
        log_fail "Rollback verification failed: $rolled_back_image"
        return 1
    fi
    
    # Step 7: Verify rollback CSV was created
    log_test "Verifying rollback CSV creation"
    if [[ -f "$rollback_csv" ]] && [[ $(wc -l < "$rollback_csv") -gt 1 ]]; then
        log_pass "Rollback CSV created with data"
    else
        log_fail "Rollback CSV not created or empty"
        return 1
    fi
    
    # Cleanup test files
    rm -f $migration_csv $rollback_csv rollback-test-migration_rollback_*.csv
}

# Test 3: Rollback dry-run functionality
test_rollback_dry_run() {
    log_info "=== Testing Rollback Dry-Run Functionality ==="
    
    local migration_csv="dry-run-test-migration.csv"
    
    # Create a migration first
    echo "y" | $MIGRATION_SCRIPT --namespace $TEST_NAMESPACE --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY --output-csv $migration_csv >/dev/null 2>&1
    
    # Record current state
    local current_image
    current_image=$(kubectl get deployment rollback-test-app -n $TEST_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    
    # Test dry-run rollback
    log_test "Dry-run rollback does not change images"
    local rollback_backup
    rollback_backup=$(ls dry-run-test-migration_rollback_*.csv 2>/dev/null | head -1)
    
    if [[ -n "$rollback_backup" ]]; then
        $ROLLBACK_SCRIPT --dry-run --csv-file "$rollback_backup" >/dev/null 2>&1
        
        # Verify image hasn't changed
        local after_dry_run_image
        after_dry_run_image=$(kubectl get deployment rollback-test-app -n $TEST_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
        
        if [[ "$current_image" == "$after_dry_run_image" ]]; then
            log_pass "Dry-run rollback does not change images"
        else
            log_fail "Dry-run rollback changed images unexpectedly"
        fi
    else
        log_fail "Rollback backup file not found for dry-run test"
    fi
    
    # Cleanup
    rm -f $migration_csv dry-run-test-migration_rollback_*.csv
}

# Test 4: Invalid CSV file handling
test_invalid_csv_handling() {
    log_info "=== Testing Invalid CSV File Handling ==="
    
    # Test with invalid CSV header
    log_test "Invalid CSV header handling"
    local invalid_csv="invalid-header.csv"
    echo "Invalid,Header,Format" > $invalid_csv
    echo "data,row,here" >> $invalid_csv
    
    if $ROLLBACK_SCRIPT --dry-run --csv-file $invalid_csv 2>&1 | grep -q "Invalid CSV file format"; then
        log_pass "Invalid CSV header handling"
    else
        log_fail "Invalid CSV header handling"
    fi
    
    # Test with empty CSV file
    log_test "Empty CSV file handling"
    local empty_csv="empty.csv"
    echo "Timestamp,Namespace,Resource Type,Resource Name,Source Image,Destination Image,Source Registry,Destination Registry,Image Pull Secret,Migration Status" > $empty_csv
    
    if $ROLLBACK_SCRIPT --dry-run --csv-file $empty_csv 2>&1 | grep -q "appears to be empty"; then
        log_pass "Empty CSV file handling"
    else
        log_fail "Empty CSV file handling"
    fi
    
    # Cleanup
    rm -f $invalid_csv $empty_csv
}

# Test 5: Namespace filtering
test_namespace_filtering() {
    log_info "=== Testing Namespace Filtering ==="
    
    # Create a multi-namespace CSV file
    local multi_ns_csv="multi-namespace.csv"
    cat > $multi_ns_csv << EOF
Timestamp,Namespace,Resource Type,Resource Name,Source Image,Destination Image,Source Registry,Destination Registry,Image Pull Secret,Migration Status
2025-09-23 09:00:00,namespace1,deployment,app1,"old/image:v1","new/image:v1",old,new,secret,Executed
2025-09-23 09:00:00,namespace2,deployment,app2,"old/image:v2","new/image:v2",old,new,secret,Executed
2025-09-23 09:00:00,namespace1,statefulset,sts1,"old/sts:v1","new/sts:v1",old,new,secret,Executed
EOF
    
    log_test "Namespace filtering works correctly"
    local filtered_output
    filtered_output=$($ROLLBACK_SCRIPT --dry-run --csv-file $multi_ns_csv --namespace namespace1 2>&1)
    
    # Should contain namespace1 resources but not namespace2
    if echo "$filtered_output" | grep -q "namespace1" && ! echo "$filtered_output" | grep -q "namespace2"; then
        log_pass "Namespace filtering works correctly"
    else
        log_fail "Namespace filtering failed"
    fi
    
    # Cleanup
    rm -f $multi_ns_csv
}

# Test 6: Interactive mode simulation
test_interactive_mode() {
    log_info "=== Testing Interactive Mode ==="
    
    local migration_csv="interactive-test-migration.csv"
    
    # Create a migration first
    echo "y" | $MIGRATION_SCRIPT --namespace $TEST_NAMESPACE --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY --output-csv $migration_csv >/dev/null 2>&1
    
    log_test "Interactive mode quit functionality"
    local rollback_backup
    rollback_backup=$(ls interactive-test-migration_rollback_*.csv 2>/dev/null | head -1)
    
    if [[ -n "$rollback_backup" ]]; then
        # Test quit functionality
        if echo "q" | timeout 10 $ROLLBACK_SCRIPT --interactive --dry-run --csv-file "$rollback_backup" 2>&1 | grep -q "cancelled by user"; then
            log_pass "Interactive mode quit functionality"
        else
            log_fail "Interactive mode quit functionality"
        fi
    else
        log_fail "Rollback backup file not found for interactive test"
    fi
    
    # Cleanup
    rm -f $migration_csv interactive-test-migration_rollback_*.csv
}

# Cleanup test environment
cleanup_rollback_test() {
    log_info "Cleaning up rollback test environment..."
    
    # Clean up test namespace
    kubectl delete namespace $TEST_NAMESPACE --ignore-not-found=true
    
    # Clean up temporary files
    rm -f rollback-test-*.csv
    rm -f dry-run-test-*.csv
    rm -f interactive-test-*.csv
    rm -f *_rollback_*.csv
    
    log_info "Cleanup complete"
}

# Generate test report
generate_rollback_test_report() {
    echo
    echo "================================================================================"
    echo "                         ROLLBACK TEST REPORT"
    echo "================================================================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%"
    echo "================================================================================"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL ROLLBACK TESTS PASSED! Rollback functionality is production-ready.${NC}"
        return 0
    else
        echo -e "${RED}❌ Some rollback tests failed. Please review and fix issues.${NC}"
        return 1
    fi
}

# Main test execution
main() {
    echo "================================================================================"
    echo "    Kubernetes Image Migration Rollback - Comprehensive Test Suite"
    echo "================================================================================"
    echo
    
    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Error: kubectl is not installed"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is not installed"
        exit 1
    fi
    
    if [[ ! -f "$MIGRATION_SCRIPT" ]]; then
        echo "Error: Migration script not found at $MIGRATION_SCRIPT"
        exit 1
    fi
    
    if [[ ! -f "$ROLLBACK_SCRIPT" ]]; then
        echo "Error: Rollback script not found at $ROLLBACK_SCRIPT"
        exit 1
    fi
    
    # Setup test environment
    setup_rollback_test
    
    # Run all rollback tests
    test_rollback_basic_functionality
    test_end_to_end_rollback
    test_rollback_dry_run
    test_invalid_csv_handling
    test_namespace_filtering
    test_interactive_mode
    
    # Cleanup
    cleanup_rollback_test
    
    # Generate report
    generate_rollback_test_report
}

# Run main function
main "$@"
