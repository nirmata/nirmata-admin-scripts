#!/bin/bash

# 👥 Phase 2: User & Team Migration
# Run this script to migrate users and teams with role preservation

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
LOG_FILE="$LOG_DIR/phase2_users_teams_${TIMESTAMP}.log"
SUMMARY_LOG="$LOG_DIR/phase2_users_teams_summary_${TIMESTAMP}.log"

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

echo -e "${BLUE}👥 Phase 2: Users & Teams Migration${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""
echo "Source: $SOURCE_API ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API ($DEST_CLUSTER)"
echo ""
echo "📄 Log file: $LOG_FILE"
echo "📄 Summary: $SUMMARY_LOG"
echo ""

# Log start
log_message "=== Phase 2: Users & Teams Migration Started ==="
log_message "Source: $SOURCE_API ($SOURCE_CLUSTER)"
log_message "Destination: $DEST_API ($DEST_CLUSTER)"
log_message "Timestamp: $TIMESTAMP"

# Run the user and team migration with logging
echo -e "${YELLOW}👥 Migrating users and teams with role preservation...${NC}"
log_message "Starting user and team migration"

if ./copy_cluster_teams_with_full_user_roles.sh "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER" 2>&1 | tee -a "$LOG_FILE"; then
    echo ""
    echo -e "${GREEN}✅ Phase 2: Users & Teams Migration Completed Successfully${NC}"
    log_message "Phase 2 user and team migration completed successfully"
    
    # Extract summary information from the migration output
    USER_COUNT=$(grep -o "Successfully processed [0-9]* users" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "N/A")
    TEAM_COUNT=$(grep -o "Successfully processed [0-9]* teams" "$LOG_FILE" | tail -1 | grep -o "[0-9]*" || echo "N/A")
    
    # Create summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 2: Users & Teams Migration Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: SUCCESS
Duration: $(date)

Migration Results:
✅ Users migrated: $USER_COUNT
✅ Teams migrated: $TEAM_COUNT
✅ Roles preserved with merge logic
✅ Identity providers handled correctly

Key Features:
- Smart role merging (preserves existing roles)
- Team membership preservation
- SAML/Azure AD identity provider support
- Production-safe merge logic

Next Step: Run Phase 3 (Environment Migration)
EOF

    echo ""
    echo "📊 Migration Summary:"
    cat "$SUMMARY_LOG"
    
else
    echo ""
    echo -e "${RED}❌ Phase 2: Users & Teams Migration Failed${NC}"
    log_message "Phase 2 user and team migration failed"
    
    # Create failure summary
    cat > "$SUMMARY_LOG" << EOF
=== Phase 2: Users & Teams Migration Summary ===
Timestamp: $TIMESTAMP
Source: $SOURCE_API ($SOURCE_CLUSTER)
Destination: $DEST_API ($DEST_CLUSTER)
Status: FAILED
Duration: $(date)

❌ User and team migration failed - check log file for details
⚠️  Do not proceed to Phase 3 until issues are resolved

Common Issues:
1. API token permissions for user management
2. Identity provider configuration in destination
3. User invitation restrictions in production environments
4. Network connectivity or rate limiting

Troubleshooting:
- Review detailed log: $LOG_FILE
- Check API token permissions
- Verify SAML/Azure AD setup in destination
- Contact Nirmata support if needed
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
echo "🚀 Ready for Phase 3: Environment Migration" 