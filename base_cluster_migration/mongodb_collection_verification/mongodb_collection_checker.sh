#!/bin/bash

################################################################################
# MongoDB Collection Count Checker
# 
# Purpose: Check collection counts in MongoDB running in Kubernetes
# Features:
#   - Automatic PRIMARY pod detection
#   - Collection and document counting
#   - Comprehensive logging to file and console
#
# Usage:
#   ./mongodb_collection_checker.sh <namespace> [pod-name]
#
# Examples:
#   ./mongodb_collection_checker.sh pe420-qa
#   ./mongodb_collection_checker.sh pe420-qa mongodb-1
################################################################################

set -e

VERSION="1.0.0"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Directories
LOG_DIR="./logs"
REPORT_DIR="./reports"
LOG_FILE=""

# MongoDB shell command (will be detected)
MONGO_CMD=""

# Important databases to check (base names)
IMPORTANT_DBS="Activity Availability-cluster-hc Availability-env-app Catalog Cluster Config Environments Users TimeSeries"

# Databases to explicitly exclude
EXCLUDE_DBS="TimeSeries-Metrics"

################################################################################
# LOGGING FUNCTIONS
################################################################################

init_logging() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$REPORT_DIR"
    LOG_FILE="$LOG_DIR/mongodb_checker_$(date +%Y%m%d_%H%M%S).log"
    
    {
        echo "========================================"
        echo "MongoDB Collection Checker - Log"
        echo "========================================"
        echo "Version: $VERSION"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Command: $0 $*"
        echo "========================================"
        echo ""
    } > "$LOG_FILE"
}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO" "$1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS" "$1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING" "$1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR" "$1"
}

print_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
    log "DEBUG" "$1"
}

print_header() {
    echo ""
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}========================================${NC}"
    echo ""
    log "HEADER" "$1"
}

################################################################################
# MONGODB SHELL DETECTION
################################################################################

detect_mongo_shell() {
    local namespace=$1
    local pod=$2
    
    print_debug "Detecting MongoDB shell version..."
    
    # Try mongosh first (new shell)
    if kubectl exec -n "$namespace" "$pod" -- which mongosh >/dev/null 2>&1; then
        MONGO_CMD="mongosh"
        print_debug "Using mongosh (new MongoDB shell)"
        log "INFO" "Detected mongosh"
    # Fall back to mongo (old shell)
    elif kubectl exec -n "$namespace" "$pod" -- which mongo >/dev/null 2>&1; then
        MONGO_CMD="mongo"
        print_info "Using mongo (legacy shell)" >&2
        log "INFO" "Detected mongo (legacy shell)"
    else
        print_error "Neither mongosh nor mongo found in pod $pod" >&2
        log "ERROR" "No MongoDB shell found in pod"
        exit 1
    fi
}

################################################################################
# PRIMARY POD DETECTION
################################################################################

find_mongodb_pods() {
    local namespace=$1
    
    print_debug "Searching for MongoDB pods in namespace: $namespace"
    
    local pods=$(kubectl get pods -n "$namespace" -o name 2>/dev/null | grep -E "mongodb|mongo" | cut -d'/' -f2)
    
    if [ -z "$pods" ]; then
        print_error "No MongoDB pod found in namespace $namespace" >&2
        echo "" >&2
        echo "Available pods:" >&2
        kubectl get pods -n "$namespace" >&2
        log "ERROR" "No MongoDB pods found in namespace $namespace"
        exit 1
    fi
    
    print_debug "Found MongoDB pods: $(echo $pods | tr '\n' ' ')"
    echo "$pods"
}

find_primary_mongodb_pod() {
    local namespace=$1
    
    print_info "Searching for PRIMARY MongoDB pod..." >&2
    log "INFO" "Starting PRIMARY pod detection in namespace: $namespace"
    
    local pods=$(find_mongodb_pods "$namespace")
    local primary_pod=""
    
    while IFS= read -r pod; do
        if [ -z "$pod" ]; then
            continue
        fi
        
        print_info "Checking pod: $pod" >&2
        log "DEBUG" "Checking pod: $pod"
        
        # Detect MongoDB shell if not already detected
        if [ -z "$MONGO_CMD" ]; then
            detect_mongo_shell "$namespace" "$pod"
        fi
        
        local is_primary=$(kubectl exec -n "$namespace" "$pod" -- $MONGO_CMD --quiet --eval "
            try {
                var status = rs.status();
                var myState = status.members.find(m => m.self === true);
                if (myState && myState.stateStr === 'PRIMARY') {
                    print('true');
                } else {
                    print('false');
                }
            } catch (e) {
                print('standalone');
            }
        " 2>/dev/null | tail -1)
        
        log "DEBUG" "Pod $pod status: $is_primary"
        
        if [ "$is_primary" = "true" ]; then
            primary_pod="$pod"
            print_success "✓ Found PRIMARY pod: $pod" >&2
            log "SUCCESS" "PRIMARY pod identified: $pod"
            break
        elif [ "$is_primary" = "standalone" ]; then
            print_info "✓ Found STANDALONE MongoDB: $pod" >&2
            log "INFO" "Standalone MongoDB instance: $pod"
            primary_pod="$pod"
            break
        else
            print_info "  → Pod $pod is SECONDARY/ARBITER (skipping)" >&2
            log "DEBUG" "Pod $pod is not primary"
        fi
        
    done <<< "$pods"
    
    if [ -z "$primary_pod" ]; then
        print_error "No PRIMARY MongoDB pod found!" >&2
        log "ERROR" "Failed to identify PRIMARY pod"
        print_warning "Available pods:" >&2
        echo "$pods" >&2
        exit 1
    fi
    
    echo "$primary_pod"
}

################################################################################
# COLLECTION COUNT
################################################################################

check_pod_ready() {
    local namespace=$1
    local pod=$2
    
    print_debug "Checking pod status: $namespace/$pod"
    
    local status=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}' 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        print_error "Failed to get pod status for $pod"
        print_error "Error: $status"
        log "ERROR" "Failed to get pod status: $status"
        exit 1
    fi
    
    if [ -z "$status" ]; then
        print_error "Pod $pod not found in namespace $namespace"
        log "ERROR" "Pod $pod not found"
        exit 1
    fi
    
    if [ "$status" != "Running" ]; then
        print_error "Pod $pod is not running. Current status: $status"
        log "ERROR" "Pod $pod status: $status (not Running)"
        exit 1
    fi
    
    print_success "Pod $pod is Running"
    log "INFO" "Pod $pod is Running"
}

get_mongodb_collections() {
    local namespace=$1
    local pod=$2
    
    print_info "Fetching databases and collections..."
    log "INFO" "Starting collection count"
    echo ""
    
    # Create output file in reports directory
    local output_file="$REPORT_DIR/mongodb_counts_${namespace}_$(date +%Y%m%d_%H%M%S).txt"
    
    # Detect MongoDB shell version
    if [ -z "$MONGO_CMD" ]; then
        detect_mongo_shell "$namespace" "$pod"
    fi
    
    # Get replica set role
    print_debug "Getting replica set role"
    local replica_role=$(kubectl exec -n "$namespace" "$pod" -- $MONGO_CMD --quiet --eval "
        try {
            var status = rs.status();
            var myState = status.members.find(m => m.self === true);
            print(myState ? myState.stateStr : 'STANDALONE');
        } catch (e) {
            print('STANDALONE');
        }
    " 2>/dev/null | tail -1)
    
    log "INFO" "Pod role: $replica_role"
    
    # Write minimal header - only to file, not console
    {
        echo "Namespace: $namespace | Pod: $pod | Role: $replica_role | Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
    } > "$output_file"
    
    # Get databases
    print_info "Fetching database list..."
    print_info "Will check databases matching: $(echo $IMPORTANT_DBS | tr ' ' ', ')"
    if [ -n "$EXCLUDE_DBS" ]; then
        print_info "Excluding: $(echo $EXCLUDE_DBS | tr ' ' ', ')"
    fi
    log "DEBUG" "Getting database list"
    log "INFO" "Important database patterns: $IMPORTANT_DBS"
    log "INFO" "Excluded patterns: $EXCLUDE_DBS"
    
    local databases=$(kubectl exec -n "$namespace" "$pod" -- $MONGO_CMD --quiet --eval "
        db.adminCommand('listDatabases').databases
            .filter(db => !['admin', 'config', 'local'].includes(db.name))
            .map(db => db.name)
            .join('\n')
    " 2>/dev/null)
    
    if [ -z "$databases" ]; then
        print_warning "No user databases found (excluding admin, config, local)"
        log "WARNING" "No user databases found"
        
        # Try including system databases
        databases=$(kubectl exec -n "$namespace" "$pod" -- $MONGO_CMD --quiet --eval "
            db.adminCommand('listDatabases').databases.map(db => db.name).join('\n')
        " 2>/dev/null)
    fi
    
    local total_collections=0
    local total_documents=0
    local db_count=0
    local skipped_count=0
    
    # Process each database
    while IFS= read -r dbname; do
        if [ -z "$dbname" ]; then
            continue
        fi
        
        # Check if this database should be excluded
        local is_excluded=false
        for exclude_name in $EXCLUDE_DBS; do
            if [[ "$dbname" == ${exclude_name}-* ]]; then
                is_excluded=true
                print_debug "Excluding database: $dbname"
                log "DEBUG" "Excluded database: $dbname"
                skipped_count=$((skipped_count + 1))
                break
            fi
        done
        
        if [ "$is_excluded" = true ]; then
            continue
        fi
        
        # Check if this database matches important patterns
        local is_important=false
        for base_name in $IMPORTANT_DBS; do
            if [[ "$dbname" == ${base_name}-* ]]; then
                is_important=true
                break
            fi
        done
        
        if [ "$is_important" = false ]; then
            print_debug "Skipping non-important database: $dbname"
            log "DEBUG" "Skipped database: $dbname"
            skipped_count=$((skipped_count + 1))
            continue
        fi
        
        db_count=$((db_count + 1))
        print_info "Processing database [$db_count]: $dbname"
        log "INFO" "Processing database: $dbname"
        
        # Get collections
        local collections=$(kubectl exec -n "$namespace" "$pod" -- $MONGO_CMD --quiet "$dbname" --eval "
            db.getCollectionNames().join('\n')
        " 2>/dev/null)
        
        if [ -z "$collections" ]; then
            echo "$dbname: (empty)" >> "$output_file"
            print_info "  → No collections in $dbname"
            log "INFO" "Database $dbname has no collections"
            continue
        fi
        
        # Count collections for this database
        local collection_list=($collections)
        local total_colls_in_db=${#collection_list[@]}
        print_info "  → Found $total_colls_in_db collections, counting all documents..."
        
        # Write database name to file only
        echo "$dbname:" >> "$output_file"
        
        local db_collection_count=$total_colls_in_db
        local db_document_count=0
        
        # Get ALL collection counts in ONE query (much faster!)
        local all_counts=$(kubectl exec -n "$namespace" "$pod" -- $MONGO_CMD --quiet "$dbname" --eval "
            var counts = {};
            db.getCollectionNames().forEach(function(collName) {
                try {
                    counts[collName] = db.getCollection(collName).countDocuments();
                } catch(e) {
                    counts[collName] = 0;
                }
            });
            print(JSON.stringify(counts));
        " 2>/dev/null | tail -1)
        
        log "DEBUG" "Got all counts for $dbname in one query"
        
        # Parse the JSON result and write to file
        while IFS= read -r collection; do
            if [ -z "$collection" ]; then
                continue
            fi
            
            # Extract count for this collection from JSON
            local count=$(echo "$all_counts" | grep -o "\"$collection\":[0-9]*" | cut -d':' -f2)
            
            # Default to 0 if count is not found or not a number
            if [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
                count=0
                log "WARNING" "$dbname.$collection: count not found, defaulting to 0"
            fi
            
            log "DEBUG" "$dbname.$collection: $count documents"
            
            # Simple format: collection = count
            printf "  %-50s = %s\n" "$collection" "$count" >> "$output_file"
            
            db_document_count=$((db_document_count + count))
            
        done <<< "$collections"
        
        # Add database subtotal
        echo "  [Total: $db_collection_count collections, $db_document_count documents]" >> "$output_file"
        echo "" >> "$output_file"
        
        print_success "  ✓ Completed $dbname: $db_collection_count collections, $db_document_count documents"
        log "INFO" "Database $dbname: $db_collection_count collections, $db_document_count documents"
        echo ""
        
        total_collections=$((total_collections + db_collection_count))
        total_documents=$((total_documents + db_document_count))
        
    done <<< "$databases"
    
    # Write simple summary to file
    {
        echo "========================================="
        echo "SUMMARY:"
        echo "  Total Databases:   $db_count"
        echo "  Total Collections: $total_collections"
        echo "  Total Documents:   $total_documents"
        if [ $skipped_count -gt 0 ]; then
            echo "  Skipped DBs:       $skipped_count (system/other)"
        fi
        echo "========================================="
    } >> "$output_file"
    
    log "SUCCESS" "Count complete: $db_count databases, $total_collections collections, $total_documents documents"
    log "SUCCESS" "Report saved: $output_file"
    
    echo ""
    echo ""
    print_success "✓ Collection count completed!"
    echo ""
    
    # Display prominent total count box
    echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                            ║${NC}"
    echo -e "${GREEN}║         TOTAL DOCUMENT COUNT               ║${NC}"
    echo -e "${GREEN}║                                            ║${NC}"
    printf "${GREEN}║${NC}              ${YELLOW}%-27s${NC}${GREEN}║${NC}\n" "$total_documents documents"
    echo -e "${GREEN}║                                            ║${NC}"
    echo -e "${GREEN}║  Databases:   %-4s  Collections: %-5s  ║${NC}\n" "$db_count" "$total_collections" | sed "s/\(.*\)/\x1b[32m\1\x1b[0m/"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    
    print_success "📄 Report saved: $output_file"
    print_info "📋 Log saved:    $LOG_FILE"
    if [ $skipped_count -gt 0 ]; then
        print_info "ℹ️  Skipped $skipped_count system/other databases"
    fi
    echo ""
}

################################################################################
# MAIN
################################################################################

usage() {
    cat << EOF
MongoDB Collection Count Checker v${VERSION}

USAGE:
    $0 <namespace> [pod-name]

ARGUMENTS:
    namespace    Kubernetes namespace (e.g., pe420-qa)
    pod-name     (Optional) Specific pod name. If not provided, 
                 PRIMARY pod will be auto-detected

EXAMPLES:
    # Auto-detect PRIMARY pod in pe420-qa namespace
    $0 pe420-qa
    
    # Use specific pod
    $0 pe420-qa mongodb-1
    
    # Enable debug logging
    DEBUG=1 $0 pe420-qa

OUTPUT:
    - Collection count report file (mongodb_collections_YYYYMMDD_HHMMSS.txt)
    - Log file (logs/mongodb_checker_YYYYMMDD_HHMMSS.log)

COMPARISON:
    To compare source and destination after backup/restore:
    
    1. Run on source environment:
       $0 pe420-qa > source_counts.txt
    
    2. Run on destination environment:
       $0 pe420-qa > dest_counts.txt
    
    3. Compare manually:
       diff source_counts.txt dest_counts.txt
       
    Or compare the generated report files:
       diff mongodb_collections_SOURCE.txt mongodb_collections_DEST.txt

EOF
}

main() {
    local namespace="${1}"
    local pod_name="${2}"
    
    # Check for help flag
    if [ "$namespace" = "-h" ] || [ "$namespace" = "--help" ] || [ "$namespace" = "help" ]; then
        usage
        exit 0
    fi
    
    # Check required argument
    if [ -z "$namespace" ]; then
        print_error "Namespace is required"
        echo ""
        usage
        exit 1
    fi
    
    # Initialize logging
    init_logging "$@"
    
    print_header "MongoDB Collection Count Checker"
    log "INFO" "Started with namespace: $namespace, pod: ${pod_name:-auto-detect}"
    
    # Find or use provided pod
    if [ -z "$pod_name" ]; then
        pod_name=$(find_primary_mongodb_pod "$namespace")
    else
        print_info "Using specified pod: $pod_name"
        log "INFO" "Using specified pod: $pod_name"
    fi
    
    # Check pod status
    echo ""
    print_info "Using: $namespace/$pod_name"
    check_pod_ready "$namespace" "$pod_name"
    echo ""
    
    # Get collection counts
    get_mongodb_collections "$namespace" "$pod_name"
    
    print_success "✅ Done!"
    echo ""
    print_info "💡 To compare with another environment:"
    echo "   1. Run this script in the other environment"
    echo "   2. Compare the count files:"
    echo "      diff mongodb_counts_SOURCE.txt mongodb_counts_DEST.txt"
    echo ""
    print_info "   Tip: No output from diff = Perfect match!"
    echo ""
    
    log "SUCCESS" "Script completed successfully"
}

# Run
main "$@"
