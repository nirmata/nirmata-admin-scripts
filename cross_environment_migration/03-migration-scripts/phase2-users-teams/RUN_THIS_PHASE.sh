#!/bin/bash

# 👥 Phase 2: User & Team Migration
# Run this script to migrate users and teams with role preservation

set -e

echo "👥 Phase 2: User & Team Migration"
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
        echo "   Identity Provider Mode: $IDENTITY_PROVIDER_MODE"
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

echo "👥 Migrating users and teams with role preservation..."
echo ""

# Run the user & team migration
if IDENTITY_PROVIDER_MODE="$IDENTITY_PROVIDER_MODE" \
   ./copy_cluster_teams_with_full_user_roles.sh \
   "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
   "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"; then
    echo ""
    echo "✅ Phase 2 completed successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 3"
    echo "   cd ../phase3-environments"
    echo "   ./RUN_THIS_PHASE.sh"
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