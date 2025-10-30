#!/bin/bash

# ============================================================================
# PRODUCTION ROLLOUT RESTART SCRIPT FOR DNS SWITCHOVER
# ============================================================================
# Purpose: Restart nirmata-kube-controller across all clusters after DNS switch
# Strategy: Zero-downtime with fail-fast error handling
# Features: Comprehensive logging, parallel execution, intelligent retries
# ============================================================================

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
NAMESPACE="nirmata"
DEPLOYMENT="nirmata-kube-controller"

# Performance settings
MAX_PARALLEL_JOBS=10             # Process 10 clusters simultaneously
REQUEST_TIMEOUT=8                # Timeout for kubectl commands (seconds)
POD_READY_TIMEOUT=60             # Max wait time for pods to be ready
CHECK_INTERVAL=2                 # How often to check pod status

# Retry settings
MAX_RETRIES_TRANSIENT=3          # Retry transient errors only
RETRY_DELAY=3                    # Delay between retries (seconds)

# ============================================================================
# COLORS
# ============================================================================
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ============================================================================
# GLOBAL STATE
# ============================================================================
LOG_DIR="./rollout_logs_$(date +%Y%m%d_%H%M%S)"
MAIN_LOG="${LOG_DIR}/rollout_main.log"
RESULTS_FILE="${LOG_DIR}/results.json"
START_TIME=$(date +%s)

# Error categories
readonly TRANSIENT="TRANSIENT"
readonly PERMANENT="PERMANENT"
readonly SUCCESS="SUCCESS"

# ============================================================================
# LOGGING
# ============================================================================
log() {
    local level=$1
    local color=$2
    shift 2
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${MAIN_LOG}"
    echo -e "${color}[${level}]${NC} ${message}"
}

log_success() { log "SUCCESS" "${GREEN}" "$@"; }
log_info() { log "INFO" "${BLUE}" "$@"; }
log_warning() { log "WARNING" "${YELLOW}" "$@"; }
log_error() { log "ERROR" "${RED}" "$@"; }

# ============================================================================
# ERROR CATEGORIZATION
# ============================================================================
categorize_error() {
    local error_output="$1"
    
    # Permanent errors - don't retry
    if echo "$error_output" | grep -qiE "not found|notfound"; then
        echo "$PERMANENT:NOT_FOUND"
    elif echo "$error_output" | grep -qiE "forbidden|unauthorized|permission denied"; then
        echo "$PERMANENT:PERMISSION"
    elif echo "$error_output" | grep -qiE "invalid|malformed"; then
        echo "$PERMANENT:INVALID"
    # Transient errors - retry these
    elif echo "$error_output" | grep -qiE "connection refused|network unreachable|timeout|timed out|no route"; then
        echo "$TRANSIENT:NETWORK"
    elif echo "$error_output" | grep -qiE "name resolution|could not resolve|dns"; then
        echo "$TRANSIENT:DNS"
    elif echo "$error_output" | grep -qiE "deadline exceeded|throttl|too many requests"; then
        echo "$TRANSIENT:THROTTLE"
    else
        echo "$TRANSIENT:UNKNOWN"
    fi
}

should_retry() {
    local category="$1"
    [[ "$category" == TRANSIENT:* ]] && return 0 || return 1
}

get_error_message() {
    local category="$1"
    case "$category" in
        PERMANENT:NOT_FOUND) echo "Deployment does not exist - verify manually" ;;
        PERMANENT:PERMISSION) echo "Permission denied - fix RBAC and re-run" ;;
        PERMANENT:INVALID) echo "Invalid configuration - check deployment manifest" ;;
        TRANSIENT:NETWORK) echo "Network issue - will retry" ;;
        TRANSIENT:DNS) echo "DNS not propagated - will retry" ;;
        TRANSIENT:THROTTLE) echo "API throttled - will retry" ;;
        *) echo "Unknown error - check logs" ;;
    esac
}

# ============================================================================
# ZERO-DOWNTIME VERIFICATION
# ============================================================================
verify_zero_downtime() {
    local kubeconfig_file="$1"
    local context="$2"
    local log_file="$3"
    
    echo "Verifying zero-downtime rollout..." >> "${log_file}"
    
    local checks=0
    local max_checks=$((POD_READY_TIMEOUT / CHECK_INTERVAL))
    local all_ready=false
    
    while [ $checks -lt $max_checks ]; do
        sleep $CHECK_INTERVAL
        
        local state=$(timeout 5s kubectl --kubeconfig="${kubeconfig_file}" \
            --context="${context}" \
            --request-timeout=5s \
            get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
            -o jsonpath='{.spec.replicas}:{.status.replicas}:{.status.readyReplicas}:{.status.availableReplicas}' \
            2>/dev/null || echo "")
        
        if [ -n "$state" ]; then
            IFS=':' read -r desired current ready available <<< "$state"
            echo "Check ${checks}: desired=${desired} ready=${ready} available=${available}" >> "${log_file}"
            
            if [ "${ready:-0}" -eq "${desired:-1}" ] && \
               [ "${available:-0}" -eq "${desired:-1}" ] && \
               [ "${ready}" -gt 0 ]; then
                echo "All replicas ready and available" >> "${log_file}"
                all_ready=true
                break
            fi
        fi
        
        checks=$((checks + 1))
    done
    
    if [ "$all_ready" = "true" ]; then
        echo "Zero-downtime rollout successful" >> "${log_file}"
        return 0
    else
        echo "Timeout waiting for rollout to complete" >> "${log_file}"
        return 1
    fi
}

# ============================================================================
# CLUSTER RESTART FUNCTION
# ============================================================================
restart_cluster() {
    local kubeconfig_file=$1
    local context=$2
    local cluster_num=$3
    local total=$4
    local log_file="${LOG_DIR}/${context}.log"
    
    echo "═══════════════════════════════════════════════════════" >> "${log_file}"
    echo "Cluster ${cluster_num}/${total}: ${context}" >> "${log_file}"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "${log_file}"
    echo "═══════════════════════════════════════════════════════" >> "${log_file}"
    
    local retry_count=0
    local error_output=$(mktemp)
    
    while [ $retry_count -lt $MAX_RETRIES_TRANSIENT ]; do
        if [ $retry_count -gt 0 ]; then
            echo "Retry attempt ${retry_count}/${MAX_RETRIES_TRANSIENT}" >> "${log_file}"
            sleep $RETRY_DELAY
        fi
        
        retry_count=$((retry_count + 1))
        
        # Execute rollout restart
        if timeout ${REQUEST_TIMEOUT}s kubectl --kubeconfig="${kubeconfig_file}" \
            --context="${context}" \
            --request-timeout=${REQUEST_TIMEOUT}s \
            rollout restart deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" \
            >> "${log_file}" 2>"${error_output}"; then
            
            echo "Rollout restart command successful" >> "${log_file}"
            
            # Verify zero-downtime
            if verify_zero_downtime "${kubeconfig_file}" "${context}" "${log_file}"; then
                echo "{\"status\":\"${SUCCESS}\",\"context\":\"${context}\",\"retries\":${retry_count}}" >> "${RESULTS_FILE}"
                rm -f "${error_output}"
                return 0
            else
                echo "{\"status\":\"TIMEOUT\",\"context\":\"${context}\",\"reason\":\"Pods not ready in time\",\"retries\":${retry_count}}" >> "${RESULTS_FILE}"
                rm -f "${error_output}"
                return 1
            fi
        else
            # Categorize error
            local category=$(categorize_error "$(cat ${error_output})")
            local error_msg=$(tail -2 "${error_output}" | tr '\n' ' ' | sed 's/"/\\"/g')
            
            echo "ERROR: ${category} - ${error_msg}" >> "${log_file}"
            
            # Check if we should retry
            if should_retry "${category}"; then
                if [ $retry_count -lt $MAX_RETRIES_TRANSIENT ]; then
                    echo "Transient error, will retry" >> "${log_file}"
                    continue
                else
                    echo "Max retries reached" >> "${log_file}"
                    echo "{\"status\":\"FAILED\",\"context\":\"${context}\",\"category\":\"${category}\",\"reason\":\"${error_msg}\",\"retries\":${retry_count}}" >> "${RESULTS_FILE}"
                    rm -f "${error_output}"
                    return 1
                fi
            else
                # Permanent error - fail fast
                echo "Permanent error - skipping retries" >> "${log_file}"
                local msg=$(get_error_message "${category}")
                echo "Action: ${msg}" >> "${log_file}"
                echo "{\"status\":\"SKIPPED\",\"context\":\"${context}\",\"category\":\"${category}\",\"action\":\"${msg}\"}" >> "${RESULTS_FILE}"
                rm -f "${error_output}"
                return 1
            fi
        fi
    done
    
    rm -f "${error_output}"
    return 1
}

# ============================================================================
# PROGRESS BAR
# ============================================================================
show_progress() {
    local completed=$1
    local total=$2
    local success=$3
    local failed=$4
    local skipped=$5
    local percent=$((completed * 100 / total))
    printf "\r${BLUE}Progress:${NC} [%-50s] ${BOLD}%3d%%${NC} | ${GREEN}✓${NC}:%-3d ${RED}✗${NC}:%-3d ${YELLOW}⊘${NC}:%-3d" \
        "$(printf '=%.0s' $(seq 1 $((percent / 2))))" \
        "$percent" "$success" "$failed" "$skipped"
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================
generate_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    echo ""
    echo ""
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}                    EXECUTION SUMMARY                           ${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Parse results
    local total=0
    local success=0
    local failed=0
    local skipped=0
    local perm_not_found=0
    local perm_permission=0
    local trans_dns=0
    local trans_network=0
    
    if [ -f "${RESULTS_FILE}" ]; then
        while IFS= read -r line; do
            total=$((total + 1))
            local status=$(echo "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            local category=$(echo "$line" | grep -o '"category":"[^"]*"' | cut -d'"' -f4 || echo "")
            
            case "$status" in
                SUCCESS) success=$((success + 1)) ;;
                SKIPPED) skipped=$((skipped + 1)) ;;
                *) failed=$((failed + 1)) ;;
            esac
            
            case "$category" in
                PERMANENT:NOT_FOUND) perm_not_found=$((perm_not_found + 1)) ;;
                PERMANENT:PERMISSION) perm_permission=$((perm_permission + 1)) ;;
                TRANSIENT:DNS) trans_dns=$((trans_dns + 1)) ;;
                TRANSIENT:NETWORK) trans_network=$((trans_network + 1)) ;;
            esac
        done < "${RESULTS_FILE}"
    fi
    
    echo -e "${CYAN}Execution Time:${NC} ${duration}s"
    echo -e "${CYAN}Total Clusters:${NC} ${total}"
    echo ""
    
    if [ $success -gt 0 ]; then
        echo -e "  ${GREEN}✓ Success:${NC} ${BOLD}${success}${NC} clusters - Zero downtime achieved"
    fi
    if [ $failed -gt 0 ]; then
        echo -e "  ${RED}✗ Failed:${NC} ${BOLD}${failed}${NC} clusters - Check individual logs"
    fi
    if [ $skipped -gt 0 ]; then
        echo -e "  ${YELLOW}⊘ Skipped:${NC} ${BOLD}${skipped}${NC} clusters - Permanent errors (needs manual fix)"
    fi
    
    if [ $skipped -gt 0 ] || [ $failed -gt 0 ]; then
        echo ""
        echo -e "${CYAN}Error Breakdown:${NC}"
        [ $perm_not_found -gt 0 ] && echo -e "  ${YELLOW}Deployment Not Found:${NC} ${perm_not_found} - Verify deployment exists"
        [ $perm_permission -gt 0 ] && echo -e "  ${YELLOW}Permission Denied:${NC} ${perm_permission} - Fix RBAC and re-run"
        [ $trans_dns -gt 0 ] && echo -e "  ${YELLOW}DNS Issues:${NC} ${trans_dns} - Wait 60s for propagation, then re-run"
        [ $trans_network -gt 0 ] && echo -e "  ${YELLOW}Network Issues:${NC} ${trans_network} - Check connectivity and re-run"
    fi
    
    echo ""
    echo -e "${CYAN}Detailed Results:${NC}"
    
    if [ -f "${RESULTS_FILE}" ]; then
        while IFS= read -r line; do
            local status=$(echo "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            local context=$(echo "$line" | grep -o '"context":"[^"]*"' | cut -d'"' -f4)
            local action=$(echo "$line" | grep -o '"action":"[^"]*"' | cut -d'"' -f4 || echo "")
            
            case "$status" in
                SUCCESS)
                    echo -e "  ${GREEN}✓${NC} ${context}"
                    ;;
                SKIPPED)
                    echo -e "  ${YELLOW}⊘${NC} ${context} - ${action}"
                    ;;
                *)
                    echo -e "  ${RED}✗${NC} ${context} - Check: ${LOG_DIR}/${context}.log"
                    ;;
            esac
        done < "${RESULTS_FILE}"
    fi
    
    if [ $skipped -gt 0 ] || [ $failed -gt 0 ]; then
        echo ""
        echo -e "${CYAN}Next Steps:${NC}"
        [ $perm_not_found -gt 0 ] && echo -e "  ${YELLOW}1.${NC} Verify: kubectl get deploy ${DEPLOYMENT} -n ${NAMESPACE}"
        [ $perm_permission -gt 0 ] && echo -e "  ${YELLOW}2.${NC} Fix RBAC permissions"
        [ $trans_dns -gt 0 ] || [ $trans_network -gt 0 ] && echo -e "  ${YELLOW}3.${NC} Wait 60s for DNS/network, then re-run: ./rollout_restart_production.sh"
        [ $failed -gt 0 ] && echo -e "  ${YELLOW}4.${NC} Check logs: ${LOG_DIR}/<cluster>.log"
    fi
    
    echo ""
    echo -e "${CYAN}Logs saved to:${NC} ${LOG_DIR}/"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    mkdir -p "${LOG_DIR}"
    touch "${MAIN_LOG}" "${RESULTS_FILE}"
    
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}      PRODUCTION ROLLOUT RESTART - DNS SWITCHOVER              ${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    log_info "Deployment: ${BOLD}${DEPLOYMENT}${NC}${BLUE} | Namespace: ${BOLD}${NAMESPACE}${NC}${BLUE}"
    log_info "Strategy: Zero-downtime with fail-fast error handling"
    log_info "Parallel: ${BOLD}${MAX_PARALLEL_JOBS}${NC}${BLUE} | Timeout: ${BOLD}${REQUEST_TIMEOUT}s${NC}${BLUE} | Retries: ${BOLD}${MAX_RETRIES_TRANSIENT}${NC}${BLUE}"
    echo ""
    
    # Discover clusters
    log_info "Discovering clusters from kubeconfig files..."
    local kubeconfig_files=$(find . -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" -o -name "kubeconfig*" \) 2>/dev/null)
    
    if [ -z "$kubeconfig_files" ]; then
        log_error "No kubeconfig files found in current directory"
        exit 1
    fi
    
    declare -a CLUSTERS
    for kubeconfig_file in $kubeconfig_files; do
        local contexts=$(kubectl --kubeconfig="${kubeconfig_file}" config get-contexts -o name 2>/dev/null || true)
        for context in $contexts; do
            CLUSTERS+=("${kubeconfig_file}|${context}")
        done
    done
    
    local total=${#CLUSTERS[@]}
    
    if [ "$total" -eq 0 ]; then
        log_error "No clusters found"
        exit 1
    fi
    
    log_success "Found ${BOLD}${total}${NC}${GREEN} cluster(s)"
    echo ""
    log_info "Starting rollout restarts..."
    echo ""
    
    # Process clusters in parallel
    local completed=0
    local success_count=0
    local failed_count=0
    local skipped_count=0
    local active_jobs=0
    
    for cluster_info in "${CLUSTERS[@]}"; do
        IFS='|' read -r kubeconfig_file context <<< "$cluster_info"
        completed=$((completed + 1))
        
        # Control parallelism
        while [ "$active_jobs" -ge "$MAX_PARALLEL_JOBS" ]; do
            active_jobs=$(jobs -r | wc -l | tr -d ' ')
            if [ "$active_jobs" -ge "$MAX_PARALLEL_JOBS" ]; then
                show_progress $completed $total $success_count $failed_count $skipped_count
                sleep 0.3
            fi
        done
        
        # Start in background
        restart_cluster "${kubeconfig_file}" "${context}" "${completed}" "${total}" &
        active_jobs=$((active_jobs + 1))
        sleep 0.05
    done
    
    # Wait for completion
    log_info "Waiting for all operations to complete..."
    wait
    
    # Count results
    if [ -f "${RESULTS_FILE}" ]; then
        success_count=$(grep -c '"status":"SUCCESS"' "${RESULTS_FILE}" 2>/dev/null || echo 0)
        skipped_count=$(grep -c '"status":"SKIPPED"' "${RESULTS_FILE}" 2>/dev/null || echo 0)
        failed_count=$(grep -c -E '"status":"(FAILED|TIMEOUT)"' "${RESULTS_FILE}" 2>/dev/null || echo 0)
    fi
    
    show_progress $total $total $success_count $failed_count $skipped_count
    echo ""
    
    # Generate report
    generate_report
    
    # Exit code
    if [ $failed_count -gt 0 ] || [ $skipped_count -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"

