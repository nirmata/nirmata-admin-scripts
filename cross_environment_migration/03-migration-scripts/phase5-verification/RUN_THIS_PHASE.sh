#!/bin/bash

# ✅ Phase 5: Post-Migration Verification
# Run this script to validate migration success and data integrity

set -e

echo "✅ Phase 5: Post-Migration Verification"
echo "======================================="
echo ""

# Check if configuration is loaded
if [[ -z "$SOURCE_API" || -z "$DEST_API" ]]; then
    echo "⚠️  Configuration not loaded. Loading from 02-configuration/migration_config.sh..."
    echo ""
    
    # Try to load configuration
    CONFIG_FILE="../../02-configuration/migration_config.sh"
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        echo "✅ Configuration loaded successfully"
        echo "   Source: $SOURCE_API ($SOURCE_CLUSTER)"
        echo "   Destination: $DEST_API ($DEST_CLUSTER)"
        echo ""
    else
        echo "❌ Configuration file not found: $CONFIG_FILE"
        echo ""
        echo "Please:"
        echo "1. Go to 02-configuration/ directory"
        echo "2. Edit migration_config.sh with your environment details"
        echo "3. Run: source migration_config.sh"
        echo "4. Then run this script again"
        exit 1
    fi
fi

echo "✅ Running comprehensive post-migration validation..."
echo ""

# Run the verification test suite
if ../phase1-validation/run_test_suite.sh; then
    echo ""
    echo "🎉 Phase 5 completed successfully!"
    echo ""
    echo "🎊 MIGRATION COMPLETE! 🎊"
    echo "========================"
    echo ""
    echo "✅ All phases have been completed successfully:"
    echo "   📋 Phase 1: Pre-migration validation ✅"
    echo "   🏗️ Phase 2: Environment migration ✅"
    echo "   👥 Phase 3: User & team migration ✅"
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
    echo "   - Phase 2: cd ../phase2-environments && ./RUN_THIS_PHASE.sh"
    echo "   - Phase 3: cd ../phase3-users-teams && ./RUN_THIS_PHASE.sh"
    echo "   - Phase 4: cd ../phase4-applications && ./RUN_THIS_PHASE.sh"
    exit 1
fi 