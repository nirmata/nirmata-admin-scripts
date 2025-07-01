#!/bin/bash
# 🔧 Cross-Environment Migration Configuration
# Copy this file and customize with your environment details

# ================================
# SOURCE ENVIRONMENT CONFIGURATION
# ================================
export SOURCE_API="https://your-source.nirmata.co"
export SOURCE_TOKEN="your_source_api_token_here"
export SOURCE_CLUSTER="source-cluster-name"

# ================================
# DESTINATION ENVIRONMENT CONFIGURATION
# ================================
export DEST_API="https://your-dest.nirmata.co"
export DEST_TOKEN="your_destination_api_token_here"
export DEST_CLUSTER="destination-cluster-name"

# ================================
# MIGRATION SETTINGS
# ================================

# Identity Provider Mode:
# - "preserve": Keep original identity providers (SAML, Azure AD, Local)
# - "convert": Convert all to Local authentication
export IDENTITY_PROVIDER_MODE="preserve"

# Log Level: DEBUG, INFO, WARN, ERROR
export LOG_LEVEL="INFO"

# ================================
# ADVANCED SETTINGS (Optional)
# ================================

# Migration timeout (seconds)
export MIGRATION_TIMEOUT=3600

# Retry attempts for failed operations
export RETRY_ATTEMPTS=3

# Batch size for bulk operations
export BATCH_SIZE=10

# ================================
# EXAMPLE CONFIGURATIONS
# ================================

# Example 1: Production to Staging
# export SOURCE_API="https://production.nirmata.co"
# export SOURCE_TOKEN="prod_token_here"
# export SOURCE_CLUSTER="prod-cluster"
# export DEST_API="https://staging.nirmata.co"
# export DEST_TOKEN="staging_token_here"
# export DEST_CLUSTER="staging-cluster"

# Example 2: Customer Environment Migration
# export SOURCE_API="https://customer-old.nirmata.co"
# export SOURCE_TOKEN="customer_old_token"
# export SOURCE_CLUSTER="customer-cluster"
# export DEST_API="https://customer-new.nirmata.co"
# export DEST_TOKEN="customer_new_token"
# export DEST_CLUSTER="new-cluster"

# ================================
# VALIDATION
# ================================

# Uncomment to validate configuration
# echo "Configuration loaded:"
# echo "  Source: $SOURCE_API ($SOURCE_CLUSTER)"
# echo "  Destination: $DEST_API ($DEST_CLUSTER)"
# echo "  Identity Provider Mode: $IDENTITY_PROVIDER_MODE"
