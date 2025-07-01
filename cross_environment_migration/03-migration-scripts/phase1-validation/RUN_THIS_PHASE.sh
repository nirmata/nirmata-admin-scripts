#!/bin/bash

# 📋 Phase 1: Pre-Migration Validation
# Run this script to validate your environments before starting migration

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

echo "📋 Phase 1: Pre-Migration Validation"
echo "===================================="
echo ""
echo "Source: $1 ($3)"
echo "Destination: $4 ($6)"
echo ""

echo "🧪 Running comprehensive pre-migration tests..."
echo ""

# Change to the validation directory and run the test suite with arguments
cd "$(dirname "$0")"
if ./run_test_suite.sh "$1" "$2" "$3" "$4" "$5" "$6"; then
    echo ""
    echo "✅ Phase 1 completed successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 2"
    echo "   cd ../phase2-users-teams"
    echo "   ./RUN_THIS_PHASE.sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\""
    echo ""
else
    echo ""
    echo "❌ Phase 1 failed!"
    echo ""
    echo "Please:"
    echo "1. Review the test output above"
    echo "2. Fix any issues found"
    echo "3. Run this script again"
    echo ""
    echo "Common issues:"
    echo "- Check API tokens and permissions"
    echo "- Verify network connectivity"
    echo "- Ensure SAML/Azure AD is configured in destination"
    exit 1
fi 