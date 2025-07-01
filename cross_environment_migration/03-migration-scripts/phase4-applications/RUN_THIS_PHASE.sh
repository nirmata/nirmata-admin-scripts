#!/bin/bash

# 📱 Phase 4: Application Migration
# Run this script to migrate applications and update references

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

echo "📱 Phase 4: Application Migration"
echo "================================="
echo ""
echo "Source: $1 ($3)"
echo "Destination: $4 ($6)"
echo ""

echo "📱 Phase 4a: Converting Git-based applications to catalog..."
echo ""

# Change to the correct directory and run Phase 4a: Application Migration
cd "$(dirname "$0")"
if ./migrate_env_apps_to_catalog_cross_env.sh "$1" "$2" "$3" "$4" "$5" "$6"; then
    echo ""
    echo "✅ Phase 4a completed successfully!"
    echo ""
else
    echo ""
    echo "❌ Phase 4a failed!"
    echo ""
    echo "Please:"
    echo "1. Review the script output above"
    echo "2. Check logs in ../../06-logs/ directory"
    echo "3. Fix any issues found"
    echo "4. Run this script again"
    echo ""
    echo "Common issues:"
    echo "- Git credential mapping issues"
    echo "- Application creation failures"
    echo "- Catalog application naming conflicts"
    exit 1
fi

echo "🔗 Phase 4b: Updating application references in environments..."
echo ""

# Run Phase 4b: Reference Updates
if ./update_catalog_references_cross_env.sh "$1" "$2" "$3" "$4" "$5" "$6"; then
    echo ""
    echo "✅ Phase 4b completed successfully!"
    echo ""
    echo "✅ Phase 4 (Complete) finished successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 5"
    echo "   cd ../phase5-verification"
    echo "   ./RUN_THIS_PHASE.sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\""
    echo ""
    echo "💡 Verify in destination UI:"
    echo "   - Check that catalog applications were created"
    echo "   - Verify environments reference new catalog apps"
    echo "   - Test application deployments"
else
    echo ""
    echo "❌ Phase 4b failed!"
    echo ""
    echo "Please:"
    echo "1. Review the script output above"
    echo "2. Check logs in ../../06-logs/ directory"
    echo "3. Fix any issues found"
    echo "4. Run this script again"
    echo ""
    echo "Common issues:"
    echo "- Application reference update failures"
    echo "- Environment-application linking issues"
    echo "- Catalog application not found errors"
    exit 1
fi 