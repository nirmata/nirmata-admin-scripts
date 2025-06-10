#!/bin/bash

# Cross-Environment Migration Example Script
# This script demonstrates how to run migration between different Nirmata environments

# Source Environment Configuration
SOURCE_API_ENDPOINT="https://pe420.nirmata.co"
SOURCE_TOKEN="W6mdT3taq2nkLxmmJFyHfpMzrUeow0HTeQQx3/n7lvXfJYyT7l+Rd3oaSwR7NJyyRhnOQWF7nH1aNHYsEJURZg=="
SOURCE_CLUSTER="123-app-migration"

# Destination Environment Configuration
DEST_API_ENDPOINT="https://staging.nirmata.co"
DEST_TOKEN="c7/tRvOi3shNloGDjtWABf/KKckLjeNNf7q1N81uTrAMA7YXxuJ43prRuQYjR4RRFssLshsT39SxvlWIeRKNIg=="
DEST_CLUSTER="conformance-132"

echo "====================================================="
echo "Cross-Environment Migration Script"
echo "====================================================="
echo "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER)"
echo "====================================================="

# Function to prompt for confirmation
confirm_step() {
    local step_name=$1
    echo ""
    echo "About to run: $step_name"
    read -p "Do you want to proceed? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping $step_name"
        return 1
    fi
    return 0
}

# Step 1: Environment Settings Restoration
if confirm_step "Environment Settings Restoration"; then
    echo "Running environment settings restoration..."
    ./environment-restore/restore_env_settings_cross_env.sh \
        "$SOURCE_API_ENDPOINT" \
        "$SOURCE_TOKEN" \
        "$SOURCE_CLUSTER" \
        "$DEST_API_ENDPOINT" \
        "$DEST_TOKEN" \
        "$DEST_CLUSTER"
    
    if [ $? -eq 0 ]; then
        echo "✅ Environment settings restoration completed successfully"
    else
        echo "❌ Environment settings restoration failed"
        exit 1
    fi
fi

# Step 2: Application Migration to Catalog
if confirm_step "Application Migration to Catalog"; then
    echo "Running application migration to catalog..."
    ./env_to_catalog_migration/migrate_env_apps_to_catalog_cross_env.sh \
        "$SOURCE_API_ENDPOINT" \
        "$SOURCE_TOKEN" \
        "$SOURCE_CLUSTER" \
        "$DEST_API_ENDPOINT" \
        "$DEST_TOKEN" \
        "$DEST_CLUSTER"
    
    if [ $? -eq 0 ]; then
        echo "✅ Application migration completed successfully"
    else
        echo "❌ Application migration failed"
        exit 1
    fi
fi

# Step 3: Update Catalog References
if confirm_step "Update Catalog References"; then
    echo "Running catalog reference updates..."
    ./catalog-reference-update/update_catalog_references_cross_env.sh \
        "$SOURCE_API_ENDPOINT" \
        "$SOURCE_TOKEN" \
        "$SOURCE_CLUSTER" \
        "$DEST_API_ENDPOINT" \
        "$DEST_TOKEN" \
        "$DEST_CLUSTER"
    
    if [ $? -eq 0 ]; then
        echo "✅ Catalog reference updates completed successfully"
    else
        echo "❌ Catalog reference updates failed"
        exit 1
    fi
fi

echo ""
echo "====================================================="
echo "Cross-Environment Migration Completed!"
echo "====================================================="
echo "Check the logs directory for detailed execution logs:"
echo "- logs/env_restore_cross_env_*.log"
echo "- logs/migration_123-app-migration_to_conformance-132_*.log"
echo "- logs/catalog_reference_update_cross_env_*.log"
echo "=====================================================" 