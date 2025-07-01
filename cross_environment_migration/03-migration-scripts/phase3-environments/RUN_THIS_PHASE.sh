#!/bin/bash

# 🏗️ Phase 3: Environment Migration
# Run this script to migrate environment settings and team permissions

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

echo "🏗️ Phase 3: Environment Migration"
echo "================================="
echo ""
echo "Source: $1 ($3)"
echo "Destination: $4 ($6)"
echo ""

echo "🏗️ Migrating environment settings and team permissions..."
echo ""

# Change to the correct directory and run the environment migration
cd "$(dirname "$0")"
if ./restore_env_settings_cross_env.sh "$1" "$2" "$3" "$4" "$5" "$6"; then
    echo ""
    echo "✅ Phase 3 completed successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 4"
    echo "   cd ../phase4-applications"
    echo "   ./RUN_THIS_PHASE.sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\""
    echo ""
    echo "💡 Verify in destination UI:"
    echo "   - Check that environments were created"
    echo "   - Verify team permissions are in place"
else
    echo ""
    echo "❌ Phase 3 failed!"
    echo ""
    echo "Please:"
    echo "1. Review the script output above"
    echo "2. Check logs in ../../06-logs/ directory"
    echo "3. Fix any issues found"
    echo "4. Run this script again"
    echo ""
    echo "Common issues:"
    echo "- Insufficient permissions to create environments"
    echo "- Team role bindings not supported (system clusters)"
    echo "- Environment naming conflicts"
    exit 1
fi 