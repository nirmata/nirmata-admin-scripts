#!/bin/bash

# 🏗️ Phase 2: Environment Migration
# Run this script to migrate environment settings and team permissions

set -e

echo "🏗️ Phase 2: Environment Migration"
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

echo "🏗️ Migrating environment settings and team permissions..."
echo ""

# Run the environment migration
if ./restore_env_settings_cross_env.sh \
   "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
   "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"; then
    echo ""
    echo "✅ Phase 2 completed successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 3"
    echo "   cd ../phase3-users-teams"
    echo "   ./RUN_THIS_PHASE.sh"
    echo ""
    echo "💡 Verify in destination UI:"
    echo "   - Check that environments were created"
    echo "   - Verify team permissions are in place"
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
    echo "- Insufficient permissions to create environments"
    echo "- Team role bindings not supported (system clusters)"
    echo "- Environment naming conflicts"
    exit 1
fi 