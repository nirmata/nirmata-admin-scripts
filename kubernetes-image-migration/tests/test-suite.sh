#!/bin/bash

# Comprehensive Test Suite for Kubernetes Image Migration Tool
# Tests all edge cases, error scenarios, and validates production readiness

set -euo pipefail

# Test configuration
SCRIPT_PATH="./k8s-image-migration.sh"
TEST_NAMESPACE_1="test-migration-1"
TEST_NAMESPACE_2="test-migration-2"
TEST_NAMESPACE_3="test-edge-cases"
SOURCE_REGISTRY="legacy-docker-repo.company.net"
DEST_REGISTRY="ghcr.io/myorganization"
ENTERPRISE_DEST_REGISTRY="artifactory.company.net/docker-virtual"

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

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test helper functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    log_test "$test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local actual_exit_code=$?
    else
        local actual_exit_code=$?
    fi
    
    if [[ $actual_exit_code -eq $expected_exit_code ]]; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name (Expected exit code: $expected_exit_code, Got: $actual_exit_code)"
        return 1
    fi
}

run_test_with_output() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    local expected_exit_code="${4:-0}"
    
    log_test "$test_name"
    
    local output
    local actual_exit_code
    
    if output=$(eval "$test_command" 2>&1); then
        actual_exit_code=$?
    else
        actual_exit_code=$?
    fi
    
    if [[ $actual_exit_code -eq $expected_exit_code ]] && [[ $output =~ $expected_pattern ]]; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name"
        echo "Expected exit code: $expected_exit_code, Got: $actual_exit_code"
        echo "Expected pattern: $expected_pattern"
        echo "Actual output: $output"
        return 1
    fi
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Ensure kind cluster is running
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_info "Creating kind cluster..."
        kind create cluster --config kind-config.yaml --wait 60s
    fi
    
    # Clean up any existing test resources
    kubectl delete namespace $TEST_NAMESPACE_1 --ignore-not-found=true
    kubectl delete namespace $TEST_NAMESPACE_2 --ignore-not-found=true
    kubectl delete namespace $TEST_NAMESPACE_3 --ignore-not-found=true
    
    # Wait for cleanup
    sleep 5
    
    # Apply test resources
    kubectl apply -f test-resources.yaml
    
    # Create additional edge case namespace and resources
    create_edge_case_resources
    
    # Create imagePullSecrets
    kubectl create secret docker-registry artifactory-secret \
        --docker-server=ghcr.io \
        --docker-username=vikashkaushik01 \
        --docker-password=YOUR_GITHUB_TOKEN \
        -n $TEST_NAMESPACE_1 --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create secret docker-registry artifactory-secret \
        --docker-server=ghcr.io \
        --docker-username=vikashkaushik01 \
        --docker-password=YOUR_GITHUB_TOKEN \
        -n $TEST_NAMESPACE_2 --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create secret docker-registry artifactory-secret \
        --docker-server=ghcr.io \
        --docker-username=vikashkaushik01 \
        --docker-password=YOUR_GITHUB_TOKEN \
        -n $TEST_NAMESPACE_3 --dry-run=client -o yaml | kubectl apply -f -
    
    # Wait for resources to be ready
    sleep 10
    
    log_info "Test environment setup complete"
}

# Create edge case test resources
create_edge_case_resources() {
    cat << 'EOF' | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: test-edge-cases
---
# Deployment with no matching images
apiVersion: apps/v1
kind: Deployment
metadata:
  name: no-matching-images
  namespace: test-edge-cases
spec:
  replicas: 1
  selector:
    matchLabels:
      app: no-match
  template:
    metadata:
      labels:
        app: no-match
    spec:
      containers:
      - name: app
        image: nginx:latest
        ports:
        - containerPort: 80
---
# Deployment with mixed images (some match, some don't)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mixed-images
  namespace: test-edge-cases
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mixed
  template:
    metadata:
      labels:
        app: mixed
    spec:
      containers:
      - name: matching
        image: docker-repo.nibr.novartis.net/app/web:v1.0
        ports:
        - containerPort: 8080
      - name: non-matching
        image: nginx:latest
        ports:
        - containerPort: 80
      initContainers:
      - name: init-matching
        image: docker-repo.nibr.novartis.net/init/setup:v1.0
        command: ['sh', '-c', 'echo "Init completed"']
      - name: init-non-matching
        image: busybox:latest
        command: ['sh', '-c', 'echo "Init completed"']
---
# Pod with existing imagePullSecrets
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-existing-secrets
  namespace: test-edge-cases
spec:
  containers:
  - name: app
    image: docker-repo.nibr.novartis.net/app/test:v1.0
  imagePullSecrets:
  - name: existing-secret
  - name: another-secret
---
# StatefulSet with complex image paths
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: complex-images
  namespace: test-edge-cases
spec:
  serviceName: complex-images
  replicas: 1
  selector:
    matchLabels:
      app: complex
  template:
    metadata:
      labels:
        app: complex
    spec:
      containers:
      - name: app
        image: docker-repo.nibr.novartis.net/very/deep/path/with-dashes/app_name:v1.2.3-alpha.1
        ports:
        - containerPort: 8080
---
# Job with image
apiVersion: batch/v1
kind: Job
metadata:
  name: test-job
  namespace: test-edge-cases
spec:
  template:
    spec:
      containers:
      - name: job-container
        image: docker-repo.nibr.novartis.net/jobs/processor:latest
        command: ["echo", "Job completed"]
      restartPolicy: Never
EOF
}

# Test 1: Basic functionality tests
test_basic_functionality() {
    log_info "=== Testing Basic Functionality ==="
    
    # Test help command
    run_test "Help command works" \
        "$SCRIPT_PATH --help"
    
    # Test script is executable
    run_test "Script is executable" \
        "test -x $SCRIPT_PATH"
    
    # Test required parameters validation
    run_test_with_output "Missing namespace parameter fails" \
        "$SCRIPT_PATH --source-registry test --dest-registry test" \
        "Namespace is required" 1
    
    run_test_with_output "Missing source registry parameter fails" \
        "$SCRIPT_PATH --namespace test --dest-registry test" \
        "Source registry is required" 1
    
    run_test_with_output "Missing destination registry parameter fails" \
        "$SCRIPT_PATH --namespace test --source-registry test" \
        "Destination registry is required" 1
}

# Test 2: Dry-run functionality
test_dry_run_functionality() {
    log_info "=== Testing Dry-Run Functionality ==="
    
    # Test dry-run with valid namespace
    run_test "Dry-run with valid namespace" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY"
    
    # Test dry-run with non-existent namespace
    run_test_with_output "Dry-run with non-existent namespace" \
        "$SCRIPT_PATH --dry-run --namespace non-existent-ns --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY" \
        "No images found matching" 0
    
    # Test dry-run with no matching images
    run_test_with_output "Dry-run with no matching images" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_3 --source-registry non-existent-registry.com --dest-registry $DEST_REGISTRY" \
        "No images found matching" 0
}

# Test 3: CSV output functionality
test_csv_output() {
    log_info "=== Testing CSV Output Functionality ==="
    
    local csv_file="/tmp/test-migration-$(date +%s).csv"
    
    # Test CSV output generation
    run_test "CSV output generation" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY --output-csv $csv_file"
    
    # Test CSV file exists and has content
    if [[ -f "$csv_file" ]]; then
        log_pass "CSV file created successfully"
        ((PASSED_TESTS++))
    else
        log_fail "CSV file was not created"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test CSV header format
    if [[ -f "$csv_file" ]]; then
        local header=$(head -n 1 "$csv_file")
        if [[ "$header" == "Timestamp,Namespace,Resource Type,Resource Name,Source Image,Destination Image,Source Registry,Destination Registry,Image Pull Secret,Migration Status" ]]; then
            log_pass "CSV header format is correct"
            ((PASSED_TESTS++))
        else
            log_fail "CSV header format is incorrect"
            echo "Expected: Timestamp,Namespace,Resource Type,Resource Name,Source Image,Destination Image,Source Registry,Destination Registry,Image Pull Secret,Migration Status"
            echo "Got: $header"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
    fi
    
    # Test CSV content format
    if [[ -f "$csv_file" ]] && [[ $(wc -l < "$csv_file") -gt 1 ]]; then
        local sample_line=$(sed -n '2p' "$csv_file")
        if [[ "$sample_line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}, ]]; then
            log_pass "CSV content format is correct"
            ((PASSED_TESTS++))
        else
            log_fail "CSV content format is incorrect"
            echo "Sample line: $sample_line"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
    fi
    
    # Cleanup
    rm -f "$csv_file"
}

# Test 4: JSON output functionality
test_json_output() {
    log_info "=== Testing JSON Output Functionality ==="
    
    local json_file="/tmp/test-migration-$(date +%s).json"
    
    # Test JSON output generation
    run_test "JSON output generation" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY --output-plan $json_file"
    
    # Test JSON file exists and is valid JSON
    if [[ -f "$json_file" ]]; then
        if jq . "$json_file" >/dev/null 2>&1; then
            log_pass "JSON file is valid JSON"
            ((PASSED_TESTS++))
        else
            log_fail "JSON file is not valid JSON"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
    fi
    
    # Test JSON structure
    if [[ -f "$json_file" ]]; then
        if jq -e '.config.namespace' "$json_file" >/dev/null 2>&1 && \
           jq -e '.config.source_registry' "$json_file" >/dev/null 2>&1 && \
           jq -e '.config.destination_registry' "$json_file" >/dev/null 2>&1 && \
           jq -e '.images' "$json_file" >/dev/null 2>&1; then
            log_pass "JSON structure is correct"
            ((PASSED_TESTS++))
        else
            log_fail "JSON structure is incorrect"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
    fi
    
    # Cleanup
    rm -f "$json_file"
}

# Test 5: Edge cases and error handling
test_edge_cases() {
    log_info "=== Testing Edge Cases and Error Handling ==="
    
    # Test with namespace that has no matching images
    run_test_with_output "Namespace with no matching images" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_3 --source-registry non-existent-registry.com --dest-registry $DEST_REGISTRY" \
        "No images found matching" 0
    
    # Test with invalid characters in registry names
    run_test "Invalid characters in registry names" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry 'invalid registry name' --dest-registry $DEST_REGISTRY" 1
    
    # Test with very long registry names
    local long_registry="very-long-registry-name-that-exceeds-normal-limits-and-might-cause-issues-with-some-systems.example.com"
    run_test "Very long registry names" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $long_registry --dest-registry $DEST_REGISTRY"
    
    # Test with special characters in namespace
    run_test "Special characters in namespace" \
        "$SCRIPT_PATH --dry-run --namespace 'invalid-namespace!' --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY" 1
    
    # Test with empty parameters
    run_test "Empty namespace parameter" \
        "$SCRIPT_PATH --dry-run --namespace '' --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY" 1
    
    run_test "Empty source registry parameter" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry '' --dest-registry $DEST_REGISTRY" 1
    
    run_test "Empty destination registry parameter" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry ''" 1
}

# Test 6: Resource type coverage
test_resource_type_coverage() {
    log_info "=== Testing Resource Type Coverage ==="
    
    # Test that all resource types are detected
    local output
    output=$($SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_3 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY 2>&1)
    
    # Check for different resource types in output
    if echo "$output" | grep -q "deployment/"; then
        log_pass "Deployments are detected"
        ((PASSED_TESTS++))
    else
        log_fail "Deployments are not detected"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    if echo "$output" | grep -q "statefulset/"; then
        log_pass "StatefulSets are detected"
        ((PASSED_TESTS++))
    else
        log_fail "StatefulSets are not detected"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    if echo "$output" | grep -q "job/"; then
        log_pass "Jobs are detected"
        ((PASSED_TESTS++))
    else
        log_fail "Jobs are not detected"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
}

# Test 7: ImagePullSecret handling
test_imagepullsecret_handling() {
    log_info "=== Testing ImagePullSecret Handling ==="
    
    # Test with existing imagePullSecret
    run_test "Handling existing imagePullSecrets" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_3 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY"
    
    # Test with non-existent imagePullSecret
    run_test_with_output "Warning for non-existent imagePullSecret" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY --image-pull-secret non-existent-secret" \
        "does not exist" 0
}

# Test 8: Interactive mode simulation
test_interactive_mode() {
    log_info "=== Testing Interactive Mode ==="
    
    # Test interactive mode with 'q' (quit)
    run_test_with_output "Interactive mode quit functionality" \
        "echo 'q' | $SCRIPT_PATH --interactive --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY" \
        "cancelled by user" 1
}

# Test 9: Performance and scalability
test_performance() {
    log_info "=== Testing Performance and Scalability ==="
    
    # Test with multiple namespaces (run sequentially to simulate real usage)
    local start_time=$(date +%s)
    
    $SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY >/dev/null 2>&1
    $SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_2 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY >/dev/null 2>&1
    $SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_3 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY >/dev/null 2>&1
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $duration -lt 30 ]]; then
        log_pass "Performance test completed in reasonable time ($duration seconds)"
        ((PASSED_TESTS++))
    else
        log_fail "Performance test took too long ($duration seconds)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
}

# Test 10: Actual migration test (with rollback)
test_actual_migration() {
    log_info "=== Testing Actual Migration (with rollback) ==="
    
    # Get original image for rollback
    local original_image
    original_image=$(kubectl get deployment test-app-deployment -n $TEST_NAMESPACE_1 -o jsonpath='{.spec.template.spec.containers[0].image}')
    
    # Perform actual migration on a single resource
    echo "y" | $SCRIPT_PATH --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY >/dev/null 2>&1
    
    # Check if image was updated
    local updated_image
    updated_image=$(kubectl get deployment test-app-deployment -n $TEST_NAMESPACE_1 -o jsonpath='{.spec.template.spec.containers[0].image}')
    
    if [[ "$updated_image" != "$original_image" ]] && [[ "$updated_image" == *"$DEST_REGISTRY"* ]]; then
        log_pass "Actual migration updates images correctly"
        ((PASSED_TESTS++))
    else
        log_fail "Actual migration did not update images correctly"
        echo "Original: $original_image"
        echo "Updated: $updated_image"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Check if imagePullSecret was added
    local secrets
    secrets=$(kubectl get deployment test-app-deployment -n $TEST_NAMESPACE_1 -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}')
    
    if [[ "$secrets" == *"artifactory-secret"* ]]; then
        log_pass "ImagePullSecret was added correctly"
        ((PASSED_TESTS++))
    else
        log_fail "ImagePullSecret was not added correctly"
        echo "Secrets: $secrets"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Rollback for next tests
    kubectl patch deployment test-app-deployment -n $TEST_NAMESPACE_1 -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"app\",\"image\":\"$original_image\"}]}}}}" >/dev/null 2>&1
}

# Test 11: Enterprise-specific registry format
test_enterprise_registry_format() {
    log_info "=== Testing Enterprise Registry Format ==="
    
    local csv_file="/tmp/enterprise-test-$(date +%s).csv"
    
    # Test with Enterprise JFrog registry format
    run_test "Enterprise JFrog registry format" \
        "$SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $ENTERPRISE_DEST_REGISTRY --output-csv $csv_file"
    
    # Check if the transformation is correct
    if [[ -f "$csv_file" ]] && grep -q "$ENTERPRISE_DEST_REGISTRY" "$csv_file"; then
        log_pass "Enterprise registry transformation is correct"
        ((PASSED_TESTS++))
    else
        log_fail "Enterprise registry transformation failed"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Cleanup
    rm -f "$csv_file"
}

# Test 12: Concurrent execution safety
test_concurrent_execution() {
    log_info "=== Testing Concurrent Execution Safety ==="
    
    # Run multiple dry-runs concurrently
    $SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_1 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY >/dev/null 2>&1 &
    local pid1=$!
    
    $SCRIPT_PATH --dry-run --namespace $TEST_NAMESPACE_2 --source-registry $SOURCE_REGISTRY --dest-registry $DEST_REGISTRY >/dev/null 2>&1 &
    local pid2=$!
    
    # Wait for both to complete
    wait $pid1
    local exit1=$?
    wait $pid2
    local exit2=$?
    
    if [[ $exit1 -eq 0 ]] && [[ $exit2 -eq 0 ]]; then
        log_pass "Concurrent execution completed successfully"
        ((PASSED_TESTS++))
    else
        log_fail "Concurrent execution failed (Exit codes: $exit1, $exit2)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
}

# Cleanup test environment
cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    
    # Clean up test namespaces
    kubectl delete namespace $TEST_NAMESPACE_1 --ignore-not-found=true
    kubectl delete namespace $TEST_NAMESPACE_2 --ignore-not-found=true
    kubectl delete namespace $TEST_NAMESPACE_3 --ignore-not-found=true
    
    # Clean up temporary files
    rm -f /tmp/test-migration-*.csv
    rm -f /tmp/test-migration-*.json
    rm -f /tmp/novartis-test-*.csv
    
    log_info "Cleanup complete"
}

# Generate test report
generate_test_report() {
    echo
    echo "================================================================================"
    echo "                              TEST REPORT"
    echo "================================================================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%"
    echo "================================================================================"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED! Script is production-ready.${NC}"
        return 0
    else
        echo -e "${RED}❌ Some tests failed. Please review and fix issues before production use.${NC}"
        return 1
    fi
}

# Main test execution
main() {
    echo "================================================================================"
    echo "    Kubernetes Image Migration Tool - Comprehensive Test Suite"
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
    
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        echo "Error: Migration script not found at $SCRIPT_PATH"
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment
    
    # Run all tests
    test_basic_functionality
    test_dry_run_functionality
    test_csv_output
    test_json_output
    test_edge_cases
    test_resource_type_coverage
    test_imagepullsecret_handling
    test_interactive_mode
    test_performance
    test_actual_migration
    test_enterprise_registry_format
    test_concurrent_execution
    
    # Cleanup
    cleanup_test_environment
    
    # Generate report
    generate_test_report
}

# Run main function
main "$@"
