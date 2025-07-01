#!/bin/bash

# Cross-Environment Migration Example Script
# This script demonstrates how to run migration between different Nirmata environments

# ============================================================================
# CONFIGURATION - EDIT THESE VALUES FOR YOUR ENVIRONMENT
# ============================================================================

# Source Environment Configuration
SOURCE_API_ENDPOINT="https://your-source.nirmata.co"
SOURCE_TOKEN="YOUR_SOURCE_TOKEN_HERE"
SOURCE_CLUSTER="source-cluster-name"

# Destination Environment Configuration
DEST_API_ENDPOINT="https://your-destination.nirmata.co"
DEST_TOKEN="YOUR_DESTINATION_TOKEN_HERE"
DEST_CLUSTER="destination-cluster-name"

# Identity Provider Mode: "preserve" or "convert"
IDENTITY_PROVIDER_MODE="preserve"

echo "====================================================="
echo "Cross-Environment Migration Example"
echo "====================================================="
echo "Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER)"
echo "Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER)"
echo "Identity Provider Mode: $IDENTITY_PROVIDER_MODE"
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

# Step 1: Pre-Migration Validation
if confirm_step "Pre-Migration Validation (Phase 1)"; then
    echo "Running pre-migration validation..."
    cd ../03-migration-scripts/phase1-validation
    ./run_test_suite.sh
    
    if [ $? -eq 0 ]; then
        echo "✅ Pre-migration validation completed successfully"
        cd ../../04-examples
    else
        echo "❌ Pre-migration validation failed"
        exit 1
    fi
fi

# Step 2: User & Team Migration
if confirm_step "User & Team Migration (Phase 2)"; then
    echo "Running user & team migration..."
    cd ../03-migration-scripts/phase2-users-teams
    IDENTITY_PROVIDER_MODE="$IDENTITY_PROVIDER_MODE" \
    ./copy_cluster_teams_with_full_user_roles.sh \
        "$SOURCE_API_ENDPOINT" \
        "$SOURCE_TOKEN" \
        "$SOURCE_CLUSTER" \
        "$DEST_API_ENDPOINT" \
        "$DEST_TOKEN" \
        "$DEST_CLUSTER"
    
    if [ $? -eq 0 ]; then
        echo "✅ User & team migration completed successfully"
        cd ../../04-examples
    else
        echo "❌ User & team migration failed"
        exit 1
    fi
fi

# Step 3: Environment Settings Migration
if confirm_step "Environment Settings Migration (Phase 3)"; then
    echo "Running environment settings migration..."
    cd ../03-migration-scripts/phase3-environments
    ./restore_env_settings_cross_env.sh \
        "$SOURCE_API_ENDPOINT" \
        "$SOURCE_TOKEN" \
        "$SOURCE_CLUSTER" \
        "$DEST_API_ENDPOINT" \
        "$DEST_TOKEN" \
        "$DEST_CLUSTER"
    
    if [ $? -eq 0 ]; then
        echo "✅ Environment settings migration completed successfully"
        cd ../../04-examples
    else
        echo "❌ Environment settings migration failed"
        exit 1
    fi
fi

# Step 4: Application Migration to Catalog
if confirm_step "Application Migration to Catalog (Phase 4)"; then
    echo "Running application migration to catalog..."
    cd ../03-migration-scripts/phase4-applications
    ./migrate_env_apps_to_catalog_cross_env.sh \
        "$SOURCE_API_ENDPOINT" \
        "$SOURCE_TOKEN" \
        "$SOURCE_CLUSTER" \
        "$DEST_API_ENDPOINT" \
        "$DEST_TOKEN" \
        "$DEST_CLUSTER"
    
    if [ $? -eq 0 ]; then
        echo "✅ Application migration completed successfully"
        cd ../../04-examples
    else
        echo "❌ Application migration failed"
        exit 1
    fi
fi

# Step 5: Update Catalog References
if confirm_step "Update Catalog References (Phase 4b)"; then
    echo "Running catalog reference updates..."
    cd ../03-migration-scripts/phase4-applications
    ./update_catalog_references_cross_env.sh \
        "$SOURCE_API_ENDPOINT" \
        "$SOURCE_TOKEN" \
        "$SOURCE_CLUSTER" \
        "$DEST_API_ENDPOINT" \
        "$DEST_TOKEN" \
        "$DEST_CLUSTER"
    
    if [ $? -eq 0 ]; then
        echo "✅ Catalog reference updates completed successfully"
        cd ../../04-examples
    else
        echo "❌ Catalog reference updates failed"
        exit 1
    fi
fi

# Step 6: Post-Migration Validation
if confirm_step "Post-Migration Validation (Phase 5)"; then
    echo "Running post-migration validation..."
    cd ../03-migration-scripts/phase5-verification
    ./run_test_suite.sh --mode=post-migration
    
    if [ $? -eq 0 ]; then
        echo "✅ Post-migration validation completed successfully"
        cd ../../04-examples
    else
        echo "❌ Post-migration validation failed"
        exit 1
    fi
fi

echo ""
echo "====================================================="
echo "🎉 Cross-Environment Migration Completed!"
echo "====================================================="
echo "📋 Check the logs directory for detailed execution logs:"
echo "- ../06-logs/ contains all migration logs"
echo "- Review logs for any warnings or issues"
echo ""
echo "🔍 Next Steps:"
echo "1. Verify users can login to destination environment"
echo "2. Test application functionality in destination"
echo "3. Validate environment configurations are correct"
echo "=====================================================" 