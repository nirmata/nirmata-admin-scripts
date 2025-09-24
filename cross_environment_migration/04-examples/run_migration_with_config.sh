#!/bin/bash

# Cross-Environment Migration Runner with Configuration
# This script uses configuration files to run the migration process

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration file paths
CONFIG_FILE="$SCRIPT_DIR/migration_config_local.sh"
TEMPLATE_CONFIG="$SCRIPT_DIR/migration_config.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if configuration file exists
check_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
        echo ""
        echo "Please create the configuration file by:"
        echo "1. cp $TEMPLATE_CONFIG $CONFIG_FILE"
        echo "2. Edit $CONFIG_FILE with your actual values"
        echo "3. Run this script again"
        exit 1
    fi
}

# Load configuration
load_config() {
    log "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    # Validate required variables
    if [[ -z "${SOURCE_API_ENDPOINT:-}" ]] || [[ -z "${SOURCE_API_TOKEN:-}" ]] || [[ -z "${SOURCE_CLUSTER_NAME:-}" ]]; then
        error "Source environment configuration is incomplete"
        exit 1
    fi
    
    if [[ -z "${DEST_API_ENDPOINT:-}" ]] || [[ -z "${DEST_API_TOKEN:-}" ]] || [[ -z "${DEST_CLUSTER_NAME:-}" ]]; then
        error "Destination environment configuration is incomplete"
        exit 1
    fi
    
    # Check for placeholder tokens
    if [[ "$SOURCE_API_TOKEN" == "YOUR_SOURCE_API_TOKEN_HERE" ]] || [[ "$DEST_API_TOKEN" == "YOUR_DEST_API_TOKEN_HERE" ]]; then
        error "Please update the API tokens in $CONFIG_FILE"
        exit 1
    fi
}

# Validate authentication
validate_auth() {
    if [[ "${VALIDATE_AUTH:-true}" == "true" ]]; then
        log "Validating authentication..."
        
        # Test source environment
        log "Testing source environment access..."
        if ! curl -s -f -H "Authorization: NIRMATA-API $SOURCE_API_TOKEN" "$SOURCE_API_ENDPOINT/environments/api/clusters" > /dev/null; then
            error "Failed to authenticate with source environment: $SOURCE_API_ENDPOINT"
            exit 1
        fi
        success "Source environment authentication successful"
        
        # Test destination environment
        log "Testing destination environment access..."
        if ! curl -s -f -H "Authorization: NIRMATA-API $DEST_API_TOKEN" "$DEST_API_ENDPOINT/environments/api/clusters" > /dev/null; then
            error "Failed to authenticate with destination environment: $DEST_API_ENDPOINT"
            exit 1
        fi
        success "Destination environment authentication successful"
    fi
}

# Create log directory
setup_logging() {
    LOG_DIR="${LOG_DIR:-logs}"
    mkdir -p "$PARENT_DIR/$LOG_DIR"
    log "Log directory: $PARENT_DIR/$LOG_DIR"
}

# Run environment settings restore
run_env_restore() {
    if [[ "${RUN_ENV_RESTORE:-true}" == "true" ]]; then
        log "Starting environment settings restoration..."
        
        if "$PARENT_DIR/03-migration-scripts/phase2-environments/restore_env_settings_cross_env.sh" \
            "$SOURCE_API_ENDPOINT" \
            "$SOURCE_API_TOKEN" \
            "$SOURCE_CLUSTER_NAME" \
            "$DEST_API_ENDPOINT" \
            "$DEST_API_TOKEN" \
            "$DEST_CLUSTER_NAME"; then
            success "Environment settings restoration completed"
        else
            error "Environment settings restoration failed"
            return 1
        fi
    else
        log "Skipping environment settings restoration (disabled in config)"
    fi
}

# Run application migration
run_app_migration() {
    if [[ "${RUN_APP_MIGRATION:-true}" == "true" ]]; then
        log "Starting application migration to catalog..."
        
        if "$PARENT_DIR/03-migration-scripts/phase4-applications/migrate_env_apps_to_catalog_cross_env.sh" \
            "$SOURCE_API_ENDPOINT" \
            "$SOURCE_API_TOKEN" \
            "$SOURCE_CLUSTER_NAME" \
            "$DEST_API_ENDPOINT" \
            "$DEST_API_TOKEN" \
            "$DEST_CLUSTER_NAME"; then
            success "Application migration completed"
        else
            error "Application migration failed"
            return 1
        fi
    else
        log "Skipping application migration (disabled in config)"
    fi
}

# Run catalog references update
run_catalog_references() {
    if [[ "${RUN_CATALOG_REFERENCES:-true}" == "true" ]]; then
        log "Starting catalog references update..."
        
        if "$PARENT_DIR/03-migration-scripts/phase4-applications/update_catalog_references_cross_env.sh" \
            "$SOURCE_API_ENDPOINT" \
            "$SOURCE_API_TOKEN" \
            "$SOURCE_CLUSTER_NAME" \
            "$DEST_API_ENDPOINT" \
            "$DEST_API_TOKEN" \
            "$DEST_CLUSTER_NAME"; then
            success "Catalog references update completed"
        else
            warning "Catalog references update had issues (check logs)"
            return 0  # Don't fail completely as this step often has issues
        fi
    else
        log "Skipping catalog references update (disabled in config)"
    fi
}

# Main execution
main() {
    echo "=================================="
    echo "Cross-Environment Migration Runner"
    echo "=================================="
    echo ""
    
    # Setup
    check_config
    load_config
    setup_logging
    validate_auth
    
    # Display configuration
    log "Migration Configuration:"
    echo "  Source: $SOURCE_API_ENDPOINT ($SOURCE_CLUSTER_NAME)"
    echo "  Destination: $DEST_API_ENDPOINT ($DEST_CLUSTER_NAME)"
    echo ""
    
    # Run migration steps
    if [[ "${RUN_ALL_STEPS:-true}" == "true" ]]; then
        log "Running all migration steps..."
        
        # Step 1: Environment Settings
        if ! run_env_restore; then
            error "Migration failed at environment restore step"
            exit 1
        fi
        
        # Step 2: Application Migration
        if ! run_app_migration; then
            error "Migration failed at application migration step"
            exit 1
        fi
        
        # Step 3: Catalog References (allow to continue even if it fails)
        run_catalog_references
        
    else
        log "Running individual steps as configured..."
        
        # Run individual steps based on configuration
        if [[ "${RUN_ENV_RESTORE:-false}" == "true" ]]; then
            run_env_restore
        fi
        
        if [[ "${RUN_APP_MIGRATION:-false}" == "true" ]]; then
            run_app_migration
        fi
        
        if [[ "${RUN_CATALOG_REFERENCES:-false}" == "true" ]]; then
            run_catalog_references
        fi
    fi
    
    # Final summary
    echo ""
    echo "=================================="
    success "Migration process completed!"
    echo "=================================="
    echo ""
    echo "Next steps:"
    echo "1. Check the logs in: $PARENT_DIR/$LOG_DIR/"
    echo "2. Verify in destination Nirmata UI:"
    echo "   - Catalogs: Check for created catalogs"
    echo "   - Applications: Verify catalog applications"  
    echo "   - Environments: Confirm team permissions"
    echo "3. Test application deployments"
    echo "4. Manually link applications to catalogs if needed"
    echo ""
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo ""
        echo "Cross-Environment Migration Runner"
        echo ""
        echo "This script runs the cross-environment migration process using"
        echo "configuration from migration_config_local.sh"
        echo ""
        echo "Setup:"
        echo "1. cp migration_config.sh migration_config_local.sh"
        echo "2. Edit migration_config_local.sh with your values"
        echo "3. Run: $0"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac 