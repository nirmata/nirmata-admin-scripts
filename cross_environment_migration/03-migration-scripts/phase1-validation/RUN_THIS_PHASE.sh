#!/bin/bash

# 📋 Phase 1: Pre-Migration Validation
# Run this script to validate your environments before starting migration

set -e

# Function to show usage
show_usage() {
    echo "❌ Error: Exactly 6 arguments required"
    echo ""
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
    echo "  $0 https://staging.nirmata.co TOKEN1 source-cluster https://pe420.nirmata.co TOKEN2 dest-cluster"
    exit 1
}

# Check if correct number of arguments provided
if [ $# -ne 6 ]; then
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

# Setup logging
LOG_DIR="../../06-logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/phase1_validation_${TIMESTAMP}.log"
SUMMARY_LOG="$LOG_DIR/phase1_validation_summary_${TIMESTAMP}.log"

# Logging function
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}📋 Phase 1: Pre-Migration Validation${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo "Source: $SOURCE_API ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API ($DEST_CLUSTER)"
echo ""
echo "📄 Log file: $LOG_FILE"
echo "📄 Summary: $SUMMARY_LOG"
echo ""

# Log start
log_message "=== Phase 1: Pre-Migration Validation Started ==="
log_message "Source: $SOURCE_API ($SOURCE_CLUSTER)"
log_message "Destination: $DEST_API ($DEST_CLUSTER)"
log_message "Timestamp: $TIMESTAMP"

# Run the test suite with logging
echo -e "${YELLOW}🧪 Running comprehensive validation tests...${NC}"
log_message "Starting validation test suite"

# Change to the correct directory first
cd "$(dirname "$0")"

if ./run_test_suite.sh "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER" 2>&1 | tee -a "$LOG_FILE"; then
    echo ""
    echo -e "${GREEN}✅ Phase 1: Pre-Migration Validation Completed Successfully${NC}"
    log_message "Phase 1 validation completed successfully"
    
    # Create summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 1: Pre-Migration Validation Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: SUCCESS
Duration: $(date)

Key Validations:
✅ API connectivity verified
✅ Authentication confirmed
✅ Environment compatibility checked
✅ Prerequisites validated

Next Step: Run Phase 2 (Users & Teams Migration)
EOF

    echo ""
    echo "📊 Validation Summary:"
    cat "$SUMMARY_LOG"
    
else
    echo ""
    echo -e "${RED}❌ Phase 1: Pre-Migration Validation Failed${NC}"
    log_message "Phase 1 validation failed"
    
    # Create failure summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 1: Pre-Migration Validation Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: FAILED
Duration: $(date)

❌ Validation failed - check log file for details
⚠️  Do not proceed to Phase 2 until issues are resolved

Troubleshooting:
1. Check API tokens and permissions
2. Verify network connectivity
3. Ensure clusters exist in both environments
4. Review detailed log: $LOG_FILE
EOF

    echo ""
    echo "📊 Validation Summary:"
    cat "$SUMMARY_LOG"
    
    exit 1
fi

echo ""
echo "📁 Log files created:"
echo "   Detailed log: $LOG_FILE"
echo "   Summary: $SUMMARY_LOG"
echo ""
echo "🚀 Ready for Phase 2: Users & Teams Migration" 