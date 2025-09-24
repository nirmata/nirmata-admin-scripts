#!/bin/bash

# 📱 Phase 4: Application Migration
# Run this script to migrate applications and update references

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
LOG_FILE="$LOG_DIR/phase4_applications_${TIMESTAMP}.log"
SUMMARY_LOG="$LOG_DIR/phase4_applications_summary_${TIMESTAMP}.log"

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
NC='\033[0m' # No Color

echo -e "${BLUE}📱 Phase 4: Application Migration${NC}"
echo -e "${BLUE}==================================${NC}"
echo ""
echo "Source: $SOURCE_API ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API ($DEST_CLUSTER)"
echo ""
echo "📄 Log file: $LOG_FILE"
echo "📄 Summary: $SUMMARY_LOG"
echo ""

# Log start
log_message "=== Phase 4: Application Migration Started ==="
log_message "Source: $SOURCE_API ($SOURCE_CLUSTER)"
log_message "Destination: $DEST_API ($DEST_CLUSTER)"
log_message "Timestamp: $TIMESTAMP"

echo -e "${YELLOW}📱 Step 4a: Converting Git-based applications to catalog...${NC}"
log_message "Starting Step 4a: Git to catalog migration"

# Change to the correct directory first
cd "$(dirname "$0")"

STEP4A_SUCCESS=false
if ./migrate_env_apps_to_catalog_cross_env.sh "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER" 2>&1 | tee -a "$LOG_FILE"; then
    echo ""
    echo -e "${GREEN}✅ Phase 4a completed successfully!${NC}"
    log_message "Step 4a completed successfully"
    STEP4A_SUCCESS=true
else
    echo ""
    echo -e "${RED}❌ Phase 4a failed!${NC}"
    log_message "Step 4a failed"
fi

echo "🔗 Phase 4b: Updating application references in environments..."
echo ""

# Run Phase 4b: Reference Updates
STEP4B_SUCCESS=false
if ./update_catalog_references_cross_env.sh "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER" 2>&1 | tee -a "$LOG_FILE"; then
    echo ""
    echo -e "${GREEN}✅ Phase 4b completed successfully!${NC}"
    log_message "Step 4b completed successfully"
    STEP4B_SUCCESS=true
else
    echo ""
    echo -e "${RED}❌ Phase 4b failed!${NC}"
    log_message "Step 4b failed"
fi

# Overall phase result
echo ""
if [[ "$STEP4A_SUCCESS" == "true" && "$STEP4B_SUCCESS" == "true" ]]; then
    echo -e "${GREEN}✅ Phase 4: Application Migration Completed Successfully${NC}"
    log_message "Phase 4 application migration completed successfully"
    
    # Extract summary information from the migration output
    GIT_APPS=$(grep -o "Git-based applications found: [0-9]*" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "0")
    CATALOG_APPS=$(grep -o "Successfully created catalog apps: [0-9]*" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "0")
    APPS_PROCESSED=$(grep -o "Applications processed: [0-9]*" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "0")
    REFS_UPDATED=$(grep -o "References updated: [0-9]*" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "0")
    
    # Create summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 4: Application Migration Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: SUCCESS
Duration: $(date)

Migration Results:
✅ Git-based applications found: $GIT_APPS
✅ Catalog applications created: $CATALOG_APPS
✅ Applications processed: $APPS_PROCESSED
✅ References updated: $REFS_UPDATED

Key Features:
- Git-based to catalog application conversion
- Application reference updates
- Git credential mapping
- Environment linking preservation

Next Step: Run Phase 5 (Post-Migration Verification)
EOF

    echo ""
    echo "📊 Migration Summary:"
    cat "$SUMMARY_LOG"
    
    echo ""
    echo "✅ Phase 4 (Complete) finished successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 5"
    echo "   cd ../phase5-verification"
    echo "   ./RUN_THIS_PHASE.sh \"$SOURCE_API\" \"$SOURCE_TOKEN\" \"$SOURCE_CLUSTER\" \"$DEST_API\" \"$DEST_TOKEN\" \"$DEST_CLUSTER\""
    echo ""
    echo "💡 Verify in destination UI:"
    echo "   - Check that catalog applications were created"
    echo "   - Verify environments reference new catalog apps"
    echo "   - Test application deployments"
    
elif [[ "$STEP4A_SUCCESS" == "true" && "$STEP4B_SUCCESS" == "false" ]]; then
    echo -e "${YELLOW}⚠️ Phase 4: Partial Success (Step 4a completed, Step 4b failed)${NC}"
    log_message "Phase 4 partially completed - Step 4a success, Step 4b failed"
    
    # Create partial success summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 4: Application Migration Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: PARTIAL SUCCESS
Duration: $(date)

⚠️ Step 4a succeeded but Step 4b failed
✅ Git applications converted to catalog
❌ Reference updates failed

Action Required:
1. Review Step 4b errors in log file
2. Fix any issues (e.g., environment references)
3. Re-run Step 4b manually or entire Phase 4

Troubleshooting:
- Check environment IDs and application references
- Verify catalog applications were created correctly
- Review detailed log: $LOG_FILE
EOF

    echo ""
    echo "📊 Migration Summary:"
    cat "$SUMMARY_LOG"
    
    exit 1
    
else
    echo -e "${RED}❌ Phase 4: Application Migration Failed${NC}"
    log_message "Phase 4 application migration failed"
    
    # Create failure summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 4: Application Migration Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: FAILED
Duration: $(date)

❌ Application migration failed - check log file for details
⚠️  Do not proceed to Phase 5 until issues are resolved

Common Issues:
1. No Git-based applications found (this is normal for catalog-only environments)
2. Git credential mapping failures
3. Application creation permissions
4. Repository access problems

Troubleshooting:
- Check if source has Git-based applications
- Verify Git credentials in destination
- Check API token permissions for catalog management
- Review detailed log: $LOG_FILE
EOF

    echo ""
    echo "📊 Migration Summary:"
    cat "$SUMMARY_LOG"
    
    exit 1
fi

echo ""
echo "📁 Log files created:"
echo "   Detailed log: $LOG_FILE"
echo "   Summary: $SUMMARY_LOG"
echo ""
echo "🚀 Ready for Phase 5: Post-Migration Verification" 