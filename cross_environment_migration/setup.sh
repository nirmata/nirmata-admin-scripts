#!/bin/bash

# Cross-Environment Migration Setup Script
# This script helps you get started with cross-environment migration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "Cross-Environment Migration Setup"
echo "=========================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if config file already exists
CONFIG_FILE="$SCRIPT_DIR/examples/migration_config_local.sh"
TEMPLATE_FILE="$SCRIPT_DIR/examples/migration_config.sh"

if [[ -f "$CONFIG_FILE" ]]; then
    warning "Configuration file already exists: $CONFIG_FILE"
    echo ""
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Keeping existing configuration file"
        echo ""
        echo "To edit your configuration:"
        echo "  nano $CONFIG_FILE"
        echo ""
        echo "To run migration:"
        echo "  cd $SCRIPT_DIR"
        echo "  ./examples/run_migration_with_config.sh"
        exit 0
    fi
fi

# Copy template to local config
log "Creating configuration file..."
cp "$TEMPLATE_FILE" "$CONFIG_FILE"
success "Configuration file created: $CONFIG_FILE"

# Collect user input
echo ""
log "Please provide your migration configuration:"
echo ""

# Source environment
echo -e "${BLUE}Source Environment (where your apps currently are):${NC}"
read -p "Source API Endpoint (e.g., https://pe420.nirmata.co): " SOURCE_ENDPOINT
read -p "Source API Token: " SOURCE_TOKEN
read -p "Source Cluster Name (e.g., 123-app-migration): " SOURCE_CLUSTER

echo ""

# Destination environment  
echo -e "${BLUE}Destination Environment (where you want to migrate to):${NC}"
read -p "Destination API Endpoint (e.g., https://staging.nirmata.co): " DEST_ENDPOINT
read -p "Destination API Token: " DEST_TOKEN
read -p "Destination Cluster Name (e.g., conformance-132): " DEST_CLUSTER

# Update configuration file
log "Updating configuration file with your values..."

# Use sed to replace values in the config file
sed -i.bak \
    -e "s|SOURCE_API_ENDPOINT=\"https://pe420.nirmata.co\"|SOURCE_API_ENDPOINT=\"$SOURCE_ENDPOINT\"|" \
    -e "s|SOURCE_API_TOKEN=\"YOUR_SOURCE_API_TOKEN_HERE\"|SOURCE_API_TOKEN=\"$SOURCE_TOKEN\"|" \
    -e "s|SOURCE_CLUSTER_NAME=\"123-app-migration\"|SOURCE_CLUSTER_NAME=\"$SOURCE_CLUSTER\"|" \
    -e "s|DEST_API_ENDPOINT=\"https://staging.nirmata.co\"|DEST_API_ENDPOINT=\"$DEST_ENDPOINT\"|" \
    -e "s|DEST_API_TOKEN=\"YOUR_DEST_API_TOKEN_HERE\"|DEST_API_TOKEN=\"$DEST_TOKEN\"|" \
    -e "s|DEST_CLUSTER_NAME=\"conformance-132\"|DEST_CLUSTER_NAME=\"$DEST_CLUSTER\"|" \
    "$CONFIG_FILE"

# Remove backup file
rm -f "$CONFIG_FILE.bak"

success "Configuration file updated successfully!"

# Test authentication
echo ""
log "Testing authentication..."

# Test source
log "Testing source environment access..."
if curl -s -f -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_ENDPOINT/environments/api/clusters" > /dev/null; then
    success "Source environment authentication successful"
else
    warning "Source environment authentication failed - please check your credentials"
fi

# Test destination
log "Testing destination environment access..."
if curl -s -f -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_ENDPOINT/environments/api/clusters" > /dev/null; then
    success "Destination environment authentication successful"
else
    warning "Destination environment authentication failed - please check your credentials"
fi

# Setup complete
echo ""
echo "=========================================="
success "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Review your configuration:"
echo "   nano $CONFIG_FILE"
echo ""
echo "2. Run the migration:"
echo "   cd $SCRIPT_DIR"
echo "   ./examples/run_migration_with_config.sh"
echo ""
echo "3. Or run individual steps:"
echo "   ./scripts/restore_env_settings_cross_env.sh ..."
echo "   ./scripts/migrate_env_apps_to_catalog_cross_env.sh ..."
echo "   ./scripts/update_catalog_references_cross_env.sh ..."
echo ""
echo "4. Check logs in: $SCRIPT_DIR/logs/"
echo ""
echo "For help: ./examples/run_migration_with_config.sh --help"
echo ""
warning "Remember to verify results in both Nirmata environments after migration!" 