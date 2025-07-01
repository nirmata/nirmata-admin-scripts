#!/bin/bash

# ✅ Phase 5: Post-Migration Verification
# Run this script to validate migration success and data integrity

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

echo "✅ Phase 5: Post-Migration Verification"
echo "======================================="
echo ""
echo "Source: $1 ($3)"
echo "Destination: $4 ($6)"
echo ""

echo "✅ Running comprehensive post-migration validation..."
echo ""

# Run the verification test suite
if ../phase1-validation/run_test_suite.sh "$1" "$2" "$3" "$4" "$5" "$6"; then
    echo ""
    echo "🎉 Phase 5 completed successfully!"
    echo ""
    echo "🎊 MIGRATION COMPLETE! 🎊"
    echo "========================"
    echo ""
    echo "✅ All phases have been completed successfully:"
    echo "   📋 Phase 1: Pre-migration validation ✅"
    echo "   👥 Phase 2: User & team migration ✅"
    echo "   🏗️ Phase 3: Environment migration ✅"
    echo "   📱 Phase 4: Application migration ✅"
    echo "   ✅ Phase 5: Post-migration verification ✅"
    echo ""
    echo "📊 Migration Summary:"
    echo "   📁 Check logs in: ../../06-logs/"
    echo "   📋 Review detailed results in verification output above"
    echo "   🌐 Test login and functionality in destination environment"
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Test user logins in destination environment"
    echo "   2. Verify application deployments work correctly"
    echo "   3. Perform user acceptance testing"
    echo "   4. Update DNS/routing if needed"
    echo "   5. Communicate migration completion to users"
    echo ""
    echo "🎉 Congratulations! Your cross-environment migration is complete!"
else
    echo ""
    echo "❌ Phase 5 failed!"
    echo ""
    echo "⚠️  MIGRATION VALIDATION ISSUES DETECTED"
    echo ""
    echo "Please:"
    echo "1. Review the validation output above"
    echo "2. Check logs in ../../06-logs/ directory"
    echo "3. Fix any issues found"
    echo "4. Re-run specific phases if needed"
    echo "5. Run this verification script again"
    echo ""
    echo "Common issues:"
    echo "- Data integrity problems (missing users/teams/apps)"
    echo "- Permission mismatches"
    echo "- Application deployment failures"
    echo "- Identity provider authentication issues"
    echo ""
    echo "💡 You may need to re-run specific phases:"
    echo "   - Phase 2: cd ../phase2-users-teams && ./RUN_THIS_PHASE.sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\""
    echo "   - Phase 3: cd ../phase3-environments && ./RUN_THIS_PHASE.sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\""
    echo "   - Phase 4: cd ../phase4-applications && ./RUN_THIS_PHASE.sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\""
    exit 1
fi 