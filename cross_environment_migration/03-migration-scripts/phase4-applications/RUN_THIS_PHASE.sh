#!/bin/bash

# 📱 Phase 4: Application Migration
# Run this script to migrate applications and update references

set -e

echo "📱 Phase 4: Application Migration"
echo "================================="
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

echo "📱 Phase 4a: Converting Git-based applications to catalog..."
echo ""

# Run Phase 4a: Application Migration
if ./migrate_env_apps_to_catalog_cross_env.sh \
   "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
   "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"; then
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
if ./update_catalog_references_cross_env.sh \
   "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
   "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"; then
    echo ""
    echo "✅ Phase 4b completed successfully!"
    echo ""
    echo "✅ Phase 4 (Complete) finished successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 5"
    echo "   cd ../phase5-verification"
    echo "   ./RUN_THIS_PHASE.sh"
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