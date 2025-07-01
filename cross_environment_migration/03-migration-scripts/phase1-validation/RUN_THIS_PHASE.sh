#!/bin/bash

# 📋 Phase 1: Pre-Migration Validation
# Run this script to validate your environments before starting migration

set -e

echo "📋 Phase 1: Pre-Migration Validation"
echo "===================================="
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

echo "🧪 Running comprehensive pre-migration tests..."
echo ""

# Run the test suite
if ./run_test_suite.sh; then
    echo ""
    echo "✅ Phase 1 completed successfully!"
    echo ""
    echo "📋 Next Step: Run Phase 2"
    echo "   cd ../phase2-environments"
    echo "   ./RUN_THIS_PHASE.sh"
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