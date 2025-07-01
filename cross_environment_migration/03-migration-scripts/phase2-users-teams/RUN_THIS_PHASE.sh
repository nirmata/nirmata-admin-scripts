#!/bin/bash

# 👥 Phase 2: User & Team Migration
# Run this script to migrate users and teams with role preservation

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

echo "👥 Phase 2: User & Team Migration"
echo "================================="
echo ""
echo "Source: $1 ($3)"
echo "Destination: $4 ($6)"
echo ""

echo "👥 Migrating users and teams with role preservation..."
echo ""

# Change to the correct directory and run the user & team migration
cd "$(dirname "$0")"
if ./copy_cluster_teams_with_full_user_roles.sh "$1" "$2" "$3" "$4" "$5" "$6"; then
    echo ""
    echo "✅ Phase 2 completed successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 3"
    echo "   cd ../phase3-environments"
    echo "   ./RUN_THIS_PHASE.sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\""
    echo ""
    echo "💡 Verify in destination UI:"
    echo "   - Check that users were created with correct roles"
    echo "   - Verify teams have proper memberships"
    echo "   - Test user login (if using SAML/Azure AD)"
else
    echo ""
    echo "❌ Phase 2 failed!"
    echo ""
    echo "Please:"
    echo "1. Review the script output above"
    echo "2. Check logs in ../../06-logs/ directory"
    echo "3. Fix any issues found"
    echo "4. Run this script again"
    echo ""
    echo "Common issues:"
    echo "- User invitation failures (production environment restrictions)"
    echo "- Identity provider mismatches (configure SAML/Azure AD first)"
    echo "- Role assignment errors (check required roles in destination)"
    echo ""
    echo "💡 Try using convert mode if identity provider issues persist:"
    echo "   Edit migration_config.sh and set: IDENTITY_PROVIDER_MODE=\"convert\""
    exit 1
fi 