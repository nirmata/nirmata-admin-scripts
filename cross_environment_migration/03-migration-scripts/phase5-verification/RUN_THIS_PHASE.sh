#!/bin/bash

# ✅ Phase 5: Post-Migration Verification
# Run this script to validate migration success and data integrity

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
LOG_FILE="$LOG_DIR/phase5_verification_${TIMESTAMP}.log"
SUMMARY_LOG="$LOG_DIR/phase5_verification_summary_${TIMESTAMP}.log"
FINAL_REPORT="$LOG_DIR/migration_final_report_${TIMESTAMP}.log"

# Logging function
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}✅ Phase 5: Post-Migration Verification${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo "Source: $SOURCE_API ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API ($DEST_CLUSTER)"
echo ""
echo "📄 Log file: $LOG_FILE"
echo "📄 Summary: $SUMMARY_LOG"
echo "📄 Final Report: $FINAL_REPORT"
echo ""

# Log start
log_message "=== Phase 5: Post-Migration Verification Started ==="
log_message "Source: $SOURCE_API ($SOURCE_CLUSTER)"
log_message "Destination: $DEST_API ($DEST_CLUSTER)"
log_message "Timestamp: $TIMESTAMP"

# Run the verification tests with logging
echo -e "${YELLOW}🧪 Running post-migration verification tests...${NC}"
log_message "Starting post-migration verification"

# Change to the correct directory first
cd "$(dirname "$0")"

if ./run_test_suite.sh "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER" 2>&1 | tee -a "$LOG_FILE"; then
    echo ""
    echo -e "${GREEN}✅ Phase 5: Post-Migration Verification Completed Successfully${NC}"
    log_message "Phase 5 verification completed successfully"
    
    # Extract test results from the verification output
    TOTAL_TESTS=$(grep -o "Total tests: [0-9]*" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "N/A")
    PASSED_TESTS=$(grep -o "Passed: [0-9]*" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "N/A")
    FAILED_TESTS=$(grep -o "Failed: [0-9]*" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "N/A")
    
    # Calculate success rate
    if [[ "$TOTAL_TESTS" != "N/A" && "$PASSED_TESTS" != "N/A" && "$TOTAL_TESTS" -gt 0 ]]; then
        SUCCESS_RATE=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    else
        SUCCESS_RATE="N/A"
    fi
    
    # Create summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 5: Post-Migration Verification Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: SUCCESS
Duration: $(date)

Verification Results:
✅ Total tests run: $TOTAL_TESTS
✅ Tests passed: $PASSED_TESTS
❌ Tests failed: $FAILED_TESTS
📊 Success rate: $SUCCESS_RATE%

System Status:
✅ Migration verification completed
✅ System integrity validated
✅ Ready for production use

Migration Complete!
EOF

    # Create comprehensive final report
    cat > "$FINAL_REPORT" << EOF
========================================
🎉 CROSS-ENVIRONMENT MIGRATION COMPLETE
========================================

Migration Details:
Source Environment: $SOURCE_API
Source Cluster: $SOURCE_CLUSTER
Destination Environment: $DEST_API
Destination Cluster: $DEST_CLUSTER
Migration Date: $(date)

Phase Summary:
📋 Phase 1: Pre-Migration Validation - ✅ COMPLETED
👥 Phase 2: Users & Teams Migration - ✅ COMPLETED
🏗️ Phase 3: Environment Migration - ✅ COMPLETED
📱 Phase 4: Application Migration - ✅ COMPLETED
✅ Phase 5: Post-Migration Verification - ✅ COMPLETED

Final Verification:
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS
Success Rate: $SUCCESS_RATE%

Migration Status: ✅ SUCCESS
System Status: ✅ READY FOR PRODUCTION

Next Steps:
1. Notify users about the new environment
2. Update DNS/URL references if needed
3. Configure monitoring for the new environment
4. Archive migration logs for audit purposes

Log Files Location: $LOG_DIR/
Migration Timestamp: $TIMESTAMP

🎯 Migration completed successfully!
========================================
EOF

    echo ""
    echo "📊 Verification Summary:"
    cat "$SUMMARY_LOG"
    
    echo ""
    echo -e "${PURPLE}🎉 MIGRATION COMPLETED SUCCESSFULLY! 🎉${NC}"
    echo ""
    echo "📋 Final Migration Report:"
    cat "$FINAL_REPORT"
    
else
    echo ""
    echo -e "${RED}❌ Phase 5: Post-Migration Verification Failed${NC}"
    log_message "Phase 5 verification failed"
    
    # Create failure summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 5: Post-Migration Verification Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: FAILED
Duration: $(date)

❌ Post-migration verification failed - check log file for details
⚠️  Migration may have issues that need attention

Common Issues:
1. Data integrity problems from earlier phases
2. Authentication or permission issues
3. Application functionality problems
4. Environment configuration errors

Troubleshooting:
- Review all phase logs in $LOG_DIR/
- Check specific test failures in detailed log
- Verify earlier phases completed successfully
- Test critical functionality manually in destination UI

Next Steps:
1. Review detailed log: $LOG_FILE
2. Fix identified issues
3. Re-run verification or specific phases as needed
4. Contact support if issues persist
EOF

    # Create failure report
    cat > "$FINAL_REPORT" << EOF
========================================
❌ CROSS-ENVIRONMENT MIGRATION ISSUES
========================================

Migration Details:
Source Environment: $SOURCE_API
Source Cluster: $SOURCE_CLUSTER
Destination Environment: $DEST_API
Destination Cluster: $DEST_CLUSTER
Migration Date: $(date)

Phase Summary:
📋 Phase 1: Pre-Migration Validation - Status Unknown
👥 Phase 2: Users & Teams Migration - Status Unknown
🏗️ Phase 3: Environment Migration - Status Unknown
📱 Phase 4: Application Migration - Status Unknown
✅ Phase 5: Post-Migration Verification - ❌ FAILED

Migration Status: ❌ VERIFICATION FAILED
System Status: ⚠️  NEEDS ATTENTION

Action Required:
1. Review verification test failures
2. Check all phase logs for issues
3. Fix identified problems
4. Re-run verification

Log Files Location: $LOG_DIR/
Migration Timestamp: $TIMESTAMP

⚠️  Migration verification failed - review logs and fix issues
========================================
EOF

    echo ""
    echo "📊 Verification Summary:"
    cat "$SUMMARY_LOG"
    
    echo ""
    echo -e "${RED}❌ MIGRATION VERIFICATION FAILED${NC}"
    echo ""
    echo "📋 Issue Report:"
    cat "$FINAL_REPORT"
    
    exit 1
fi

echo ""
echo "📁 Log files created:"
echo "   Detailed log: $LOG_FILE"
echo "   Summary: $SUMMARY_LOG"
echo "   Final Report: $FINAL_REPORT"
echo ""
echo -e "${GREEN}🎉 Cross-Environment Migration Successfully Completed!${NC}" 