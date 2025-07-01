#!/bin/bash

# 🔧 Cross-Environment Migration Setup Script
# This script prepares your environment for cross-environment migration

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_phase() {
    echo -e "\n${PURPLE}$1${NC}"
    echo -e "${PURPLE}$(echo "$1" | sed 's/./=/g')${NC}\n"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Welcome message
echo -e "${PURPLE}"
cat << 'EOF'
🚀 Cross-Environment Migration Setup
=====================================

This setup script will:
✅ Check system prerequisites
✅ Verify required tools
✅ Set up directory structure
✅ Create configuration templates
✅ Make scripts executable
✅ Validate environment

EOF
echo -e "${NC}"

# Check system requirements
check_system_requirements() {
    log_phase "🔧 Checking System Requirements"
    
    # Check operating system
    local os_name
    case "$(uname -s)" in
        Darwin*)    os_name="macOS" ;;
        Linux*)     os_name="Linux" ;;
        CYGWIN*|MINGW*) os_name="Windows" ;;
        *)          os_name="Unknown" ;;
    esac
    
    log "Operating System: $os_name"
    
    # Check required tools
    local required_tools=("curl" "jq" "bash" "git")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local version
            case $tool in
                curl)
                    version=$(curl --version | head -n1 | cut -d' ' -f2)
                    ;;
                jq)
                    version=$(jq --version | sed 's/jq-//')
                    ;;
                bash)
                    version=$(bash --version | head -n1 | cut -d' ' -f4 | cut -d'(' -f1)
                    ;;
                git)
                    version=$(git --version | cut -d' ' -f3)
                    ;;
            esac
            log_success "$tool is available (version: $version)"
        else
            missing_tools+=("$tool")
            log_error "$tool is not installed"
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo
        log_info "Installation instructions:"
        
        for tool in "${missing_tools[@]}"; do
            case $tool in
                curl)
                    echo "  • curl: Usually pre-installed. On Ubuntu: sudo apt-get install curl"
                    ;;
                jq)
                    echo "  • jq: On macOS: brew install jq | On Ubuntu: sudo apt-get install jq"
                    ;;
                bash)
                    echo "  • bash: Usually pre-installed. Ensure version 4.0 or higher"
                    ;;
                git)
                    echo "  • git: On macOS: brew install git | On Ubuntu: sudo apt-get install git"
                    ;;
            esac
        done
        
        echo
        log_error "Please install missing tools and run setup again"
        exit 1
    fi
    
    log_success "All required tools are available"
}

# Set up directory structure
setup_directories() {
    log_phase "📁 Setting Up Directory Structure"
    
    local required_dirs=(
        "01-getting-started"
        "02-configuration"
        "03-migration-scripts/phase1-validation"
        "03-migration-scripts/phase2-environments"
        "03-migration-scripts/phase3-users-teams"
        "03-migration-scripts/phase4-applications"
        "03-migration-scripts/phase5-verification"
        "04-examples"
        "05-documentation"
        "06-logs"
    )
    
    for dir in "${required_dirs[@]}"; do
        local full_path="$SCRIPT_DIR/$dir"
        if [[ ! -d "$full_path" ]]; then
            log "Creating directory: $dir"
            mkdir -p "$full_path"
        else
            log_success "Directory exists: $dir"
        fi
    done
    
    log_success "Directory structure is ready"
}

# Make scripts executable
setup_script_permissions() {
    log_phase "🔐 Setting Up Script Permissions"
    
    # Find all .sh files and make them executable
    while IFS= read -r -d '' script; do
        if [[ ! -x "$script" ]]; then
            local relative_path="${script#$SCRIPT_DIR/}"
            log "Making executable: $relative_path"
            chmod +x "$script"
        fi
    done < <(find "$SCRIPT_DIR" -name "*.sh" -type f -print0)
    
    log_success "All scripts are now executable"
}

# Create configuration template
create_config_template() {
    log_phase "⚙️ Creating Configuration Template"
    
    local config_file="$SCRIPT_DIR/migration_config.sh"
    
    if [[ ! -f "$config_file" ]]; then
        log "Creating migration configuration template..."
        
        cat > "$config_file" << 'EOF'
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
# export DEST_API="https://your-destination.nirmata.co"
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
EOF
        
        chmod +x "$config_file"
        log_success "Configuration template created: migration_config.sh"
        log_info "Please edit migration_config.sh with your environment details"
    else
        log_success "Configuration file already exists: migration_config.sh"
    fi
}

# Validate existing scripts
validate_scripts() {
    log_phase "🧪 Validating Migration Scripts"
    
    local required_scripts=(
        "complete_migration_workflow.sh"
        "03-migration-scripts/phase1-validation/run_test_suite.sh"
        "03-migration-scripts/phase2-environments/restore_env_settings_cross_env.sh"
        "03-migration-scripts/phase3-users-teams/copy_cluster_teams_with_full_user_roles.sh"
        "03-migration-scripts/phase4-applications/migrate_env_apps_to_catalog_cross_env.sh"
        "03-migration-scripts/phase4-applications/update_catalog_references_cross_env.sh"
    )
    
    local missing_scripts=()
    
    for script in "${required_scripts[@]}"; do
        local full_path="$SCRIPT_DIR/$script"
        if [[ -f "$full_path" ]]; then
            if [[ -x "$full_path" ]]; then
                log_success "Script ready: $script"
            else
                log_warning "Script not executable: $script (fixing...)"
                chmod +x "$full_path"
                log_success "Fixed permissions: $script"
            fi
        else
            missing_scripts+=("$script")
            log_error "Missing script: $script"
        fi
    done
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "Missing required scripts: ${missing_scripts[*]}"
        log_info "Please ensure all migration scripts are present"
        return 1
    fi
    
    log_success "All migration scripts are ready"
}

# Create quick start guide
create_quick_start() {
    log_phase "📖 Creating Quick Start Guide"
    
    local quick_start_file="$SCRIPT_DIR/QUICK_START.md"
    
    if [[ ! -f "$quick_start_file" ]]; then
        cat > "$quick_start_file" << 'EOF'
# 🚀 Quick Start Guide

## Prerequisites Completed ✅
- All required tools are installed
- Directory structure is set up
- Scripts are executable
- Configuration template is ready

## Next Steps

### 1. Configure Your Migration
```bash
# Edit the configuration file with your environment details
nano migration_config.sh

# Or copy and customize for your specific use case
cp migration_config.sh my_migration_config.sh
nano my_migration_config.sh
```

### 2. Test Your Configuration
```bash
# Load configuration
source migration_config.sh

# Test connectivity to both environments
curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API/users/api/users" | jq 'length'
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" "$DEST_API/users/api/users" | jq 'length'
```

### 3. Run Migration

#### Option A: Complete Migration (Recommended)
```bash
# Run full migration workflow
./complete_migration_workflow.sh

# Or with custom config
./complete_migration_workflow.sh --config my_migration_config.sh

# Test mode (dry run)
./complete_migration_workflow.sh --test
```

#### Option B: Phase-by-Phase Migration (Recommended)
```bash
# 1. Pre-migration validation
cd ../03-migration-scripts/phase1-validation
./RUN_THIS_PHASE.sh

# 2. Environment migration
cd ../phase2-environments
./RUN_THIS_PHASE.sh

# 3. User & team migration
cd ../phase3-users-teams
./RUN_THIS_PHASE.sh

# 4. Application migration
cd ../phase4-applications
./RUN_THIS_PHASE.sh

# 5. Post-migration validation
cd ../phase5-verification
./RUN_THIS_PHASE.sh
```

### 4. Verify Results
- Check logs in `06-logs/` directory
- Verify in destination Nirmata UI
- Test application deployments
- Test user logins (especially SAML/Azure AD users)

## Need Help?
- Check the comprehensive README.md in `01-getting-started/`
- Review phase-specific documentation in `03-migration-scripts/phase*/`
- Check troubleshooting guides in `05-documentation/`
- Review migration logs in `06-logs/` for detailed information
EOF
        
        log_success "Quick start guide created: QUICK_START.md"
    else
        log_success "Quick start guide already exists"
    fi
}

# Display final instructions
show_final_instructions() {
    log_phase "🎉 Setup Complete!"
    
    echo -e "${GREEN}"
    cat << 'EOF'
✅ Your cross-environment migration toolkit is ready!

Next Steps:
1. Edit migration_config.sh with your environment details
2. Test connectivity to both environments
3. Run the migration workflow

Quick Commands:
EOF
    echo -e "${NC}"
    
    echo -e "${CYAN}# Edit configuration${NC}"
    echo "nano migration_config.sh"
    echo
    echo -e "${CYAN}# Test migration (dry run)${NC}"
    echo "./complete_migration_workflow.sh --test"
    echo
    echo -e "${CYAN}# Run full migration${NC}"
    echo "./complete_migration_workflow.sh"
    echo
    echo -e "${CYAN}# Get help${NC}"
    echo "./complete_migration_workflow.sh --help"
    echo
    
    log_info "For detailed instructions, see README.md and QUICK_START.md"
    log_info "Migration logs will be stored in the 06-logs/ directory"
}

# Main setup execution
main() {
    log "Starting cross-environment migration setup..."
    
    # Run setup steps
    check_system_requirements
    setup_directories
    setup_script_permissions
    create_config_template
    
    if validate_scripts; then
        create_quick_start
        show_final_instructions
        log_success "Setup completed successfully!"
        exit 0
    else
        log_error "Setup completed with errors"
        log_info "Please resolve missing scripts and run setup again"
        exit 1
    fi
}

# Run main function
main "$@" 