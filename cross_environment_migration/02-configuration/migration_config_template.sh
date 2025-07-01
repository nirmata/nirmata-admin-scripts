#!/bin/bash

# Cross-Environment Migration Configuration Template
# Copy this file to migration_config_local.sh and update with your values
# DO NOT commit the local config file with real tokens

# ============================================================================
# SOURCE ENVIRONMENT CONFIGURATION
# ============================================================================
SOURCE_API_ENDPOINT="https://your-source.nirmata.co"
SOURCE_API_TOKEN="YOUR_SOURCE_API_TOKEN_HERE"
SOURCE_CLUSTER_NAME="source-cluster-name"

# ============================================================================
# DESTINATION ENVIRONMENT CONFIGURATION  
# ============================================================================
DEST_API_ENDPOINT="https://your-destination.nirmata.co"
DEST_API_TOKEN="YOUR_DEST_API_TOKEN_HERE"
DEST_CLUSTER_NAME="destination-cluster-name"

# ============================================================================
# MIGRATION OPTIONS
# ============================================================================
# Set to true to run all steps, false to run individual steps
RUN_ALL_STEPS=true

# Individual step controls (only used if RUN_ALL_STEPS=false)
RUN_ENV_RESTORE=true
RUN_APP_MIGRATION=true
RUN_CATALOG_REFERENCES=true

# ============================================================================
# LOGGING OPTIONS
# ============================================================================
# Enable verbose logging
VERBOSE_LOGGING=true

# Log directory (relative to script location)
LOG_DIR="logs"

# ============================================================================
# VALIDATION OPTIONS
# ============================================================================
# Validate authentication before starting migration
VALIDATE_AUTH=true

# Check Git credential availability
CHECK_GIT_CREDENTIALS=true

# ============================================================================
# EXAMPLE REAL CONFIGURATION (TEMPLATE)
# ============================================================================
# Uncomment and modify these lines with your actual values:

# SOURCE_API_ENDPOINT="https://your-source.nirmata.co"
# SOURCE_API_TOKEN="your_actual_source_token_here"
# SOURCE_CLUSTER_NAME="your-source-cluster-name"

# DEST_API_ENDPOINT="https://your-destination.nirmata.co"  
# DEST_API_TOKEN="your_actual_destination_token_here"
# DEST_CLUSTER_NAME="your-destination-cluster-name"

# ============================================================================
# USAGE INSTRUCTIONS
# ============================================================================
# 1. Copy this file: cp migration_config.sh migration_config_local.sh
# 2. Edit migration_config_local.sh with your actual values
# 3. Run: ./run_migration_with_config.sh
# 4. Or source the config and run individual scripts:
#    source migration_config_local.sh
#    ../03-migration-scripts/phase2-environments/restore_env_settings_cross_env.sh "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER" 