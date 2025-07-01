#!/bin/bash

# 🚀 Complete Cross-Environment Migration Workflow
# This script performs end-to-end migration between different Nirmata environments
# Following the 5-phase approach: Pre-Migration → User/Team → Environment → Application → Validation

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
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

log_phase() {
    echo -e "\n${PURPLE}$1${NC}"
    echo -e "${PURPLE}$(echo "$1" | sed 's/./=/g')${NC}\n"
}

# Function to display usage
usage() {
    cat << EOF
🚀 Complete Cross-Environment Migration Workflow

Usage: $0 [options]

Options:
    -h, --help              Show this help message
    -c, --config FILE       Use configuration file (default: migration_config.sh)
    -m, --mode MODE         Migration mode: full|selective (default: full)
    -t, --test              Run in test mode (dry run)
    -v, --verbose           Enable verbose logging
    --skip-validation       Skip pre-migration validation
    --skip-post-validation  Skip post-migration validation

Configuration:
    Set these environment variables or use a config file:
    - SOURCE_API: Source Nirmata API endpoint
    - SOURCE_TOKEN: Source API token
    - SOURCE_CLUSTER: Source cluster name
    - DEST_API: Destination Nirmata API endpoint
    - DEST_TOKEN: Destination API token
    - DEST_CLUSTER: Destination cluster name
    - IDENTITY_PROVIDER_MODE: preserve|convert (default: preserve)

Examples:
    # Full migration with default config
    $0

    # Use custom config file
    $0 --config my_migration_config.sh

    # Test mode (dry run)
    $0 --test

    # Selective migration (user choice)
    $0 --mode selective

EOF
}

# Default values
CONFIG_FILE="migration_config.sh"
MIGRATION_MODE="full"
TEST_MODE=false
VERBOSE=false
SKIP_VALIDATION=false
SKIP_POST_VALIDATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -m|--mode)
            MIGRATION_MODE="$2"
            shift 2
            ;;
        -t|--test)
            TEST_MODE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --skip-post-validation)
            SKIP_POST_VALIDATION=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    log "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    log_warning "Configuration file $CONFIG_FILE not found"
    log "Please set environment variables or create a configuration file"
    
    # Check if environment variables are set
    if [[ -z "$SOURCE_API" || -z "$SOURCE_TOKEN" || -z "$SOURCE_CLUSTER" || 
          -z "$DEST_API" || -z "$DEST_TOKEN" || -z "$DEST_CLUSTER" ]]; then
        log_error "Missing required environment variables"
        log "Required: SOURCE_API, SOURCE_TOKEN, SOURCE_CLUSTER, DEST_API, DEST_TOKEN, DEST_CLUSTER"
        exit 1
    fi
fi

# Set defaults
IDENTITY_PROVIDER_MODE=${IDENTITY_PROVIDER_MODE:-"preserve"}
LOG_LEVEL=${LOG_LEVEL:-"INFO"}

# Display configuration
log_phase "🔧 Migration Configuration"
log "Source Environment: $SOURCE_API"
log "Source Cluster: $SOURCE_CLUSTER"
log "Destination Environment: $DEST_API"
log "Destination Cluster: $DEST_CLUSTER"
log "Identity Provider Mode: $IDENTITY_PROVIDER_MODE"
log "Migration Mode: $MIGRATION_MODE"
log "Test Mode: $TEST_MODE"

if [[ "$TEST_MODE" == "true" ]]; then
    log_warning "Running in TEST MODE - no actual changes will be made"
fi

# Verify script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log "Script directory: $SCRIPT_DIR"

# Check required directories and scripts
check_prerequisites() {
    log_phase "📋 Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    for tool in curl jq bash; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log "Please install missing tools and try again"
        exit 1
    fi
    
    log_success "All required tools are available"
    
    # Check script directories
    local required_dirs=("03-migration-scripts" "04-examples" "06-logs" "02-configuration")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$SCRIPT_DIR/$dir" ]]; then
            log_error "Missing required directory: $dir"
            exit 1
        fi
    done
    
    log_success "All required directories found"
    
    # Check required scripts
    local required_scripts=(
        "03-migration-scripts/phase1-validation/run_test_suite.sh"
        "03-migration-scripts/phase2-users-teams/copy_cluster_teams_with_full_user_roles.sh"
        "03-migration-scripts/phase3-environments/restore_env_settings_cross_env.sh"
        "03-migration-scripts/phase4-applications/migrate_env_apps_to_catalog_cross_env.sh"
        "03-migration-scripts/phase4-applications/update_catalog_references_cross_env.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            log_error "Missing required script: $script"
            exit 1
        fi
        
        if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
            log "Making script executable: $script"
            chmod +x "$SCRIPT_DIR/$script"
        fi
    done
    
    log_success "All required scripts found and executable"
}

# Phase 1: Pre-Migration Validation
run_pre_migration_validation() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_warning "Skipping pre-migration validation"
        return 0
    fi
    
    log_phase "📋 Phase 1: Pre-Migration Validation"
    
    log "Testing source environment connectivity..."
    if ! curl -s -f -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
         "$SOURCE_API/users/api/users" > /dev/null; then
        log_error "Failed to connect to source environment"
        log "Please check SOURCE_API and SOURCE_TOKEN"
        exit 1
    fi
    log_success "Source environment connectivity verified"
    
    log "Testing destination environment connectivity..."
    if ! curl -s -f -H "Authorization: NIRMATA-API $DEST_TOKEN" \
         "$DEST_API/users/api/users" > /dev/null; then
        log_error "Failed to connect to destination environment"
        log "Please check DEST_API and DEST_TOKEN"
        exit 1
    fi
    log_success "Destination environment connectivity verified"
    
    if [[ "$TEST_MODE" == "false" ]]; then
        log "Running comprehensive pre-migration tests..."
        cd "$SCRIPT_DIR/03-migration-scripts/phase1-validation"
        
        if ./run_test_suite.sh --mode=pre-migration; then
            log_success "Pre-migration validation completed successfully"
        else
            log_error "Pre-migration validation failed"
            log "Please resolve issues before proceeding"
            exit 1
        fi
    else
        log_warning "Skipping detailed tests in test mode"
    fi
}

# Phase 2: User & Team Migration
run_user_team_migration() {
    log_phase "👥 Phase 2: User & Team Migration"
    
    cd "$SCRIPT_DIR/03-migration-scripts/phase2-users-teams"
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "TEST MODE: Would run user & team migration"
        log "Command: IDENTITY_PROVIDER_MODE=$IDENTITY_PROVIDER_MODE ./copy_cluster_teams_with_full_user_roles.sh \"$SOURCE_API\" \"***\" \"$SOURCE_CLUSTER\" \"$DEST_API\" \"***\" \"$DEST_CLUSTER\""
        return 0
    fi
    
    log "Migrating users and teams with role preservation..."
    log "Identity Provider Mode: $IDENTITY_PROVIDER_MODE"
    
    if IDENTITY_PROVIDER_MODE="$IDENTITY_PROVIDER_MODE" \
       ./copy_cluster_teams_with_full_user_roles.sh \
       "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
       "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"; then
        log_success "User & team migration completed successfully"
    else
        log_error "User & team migration failed"
        exit 1
    fi
}

# Phase 3: Environment Migration
run_environment_migration() {
    log_phase "🏗️ Phase 3: Environment & Settings Migration"
    
    cd "$SCRIPT_DIR/03-migration-scripts/phase3-environments"
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "TEST MODE: Would run environment migration"
        log "Command: ./restore_env_settings_cross_env.sh \"$SOURCE_API\" \"***\" \"$SOURCE_CLUSTER\" \"$DEST_API\" \"***\" \"$DEST_CLUSTER\""
        return 0
    fi
    
    log "Migrating environment settings and team permissions..."
    if ./restore_env_settings_cross_env.sh \
       "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
       "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"; then
        log_success "Environment migration completed successfully"
    else
        log_error "Environment migration failed"
        exit 1
    fi
}

# Phase 4: Application Migration
run_application_migration() {
    log_phase "📱 Phase 4: Application Migration"
    
    cd "$SCRIPT_DIR/03-migration-scripts/phase4-applications"
    
    # Step 4a: Migrate Apps to Catalog
    log "Step 4a: Migrating applications to catalog..."
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "TEST MODE: Would run application to catalog migration"
        log "Command: ./migrate_env_apps_to_catalog_cross_env.sh \"$SOURCE_API\" \"***\" \"$SOURCE_CLUSTER\" \"$DEST_API\" \"***\" \"$DEST_CLUSTER\""
    else
        if ./migrate_env_apps_to_catalog_cross_env.sh \
           "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
           "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"; then
            log_success "Application to catalog migration completed"
        else
            log_warning "Application to catalog migration had issues (check logs)"
        fi
    fi
    
    # Step 4b: Update Catalog References
    log "Step 4b: Updating catalog references..."
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "TEST MODE: Would run catalog reference updates"
        log "Command: ./update_catalog_references_cross_env.sh \"$SOURCE_API\" \"***\" \"$SOURCE_CLUSTER\" \"$DEST_API\" \"***\" \"$DEST_CLUSTER\""
    else
        if ./update_catalog_references_cross_env.sh \
           "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
           "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"; then
            log_success "Catalog reference updates completed"
        else
            log_warning "Catalog reference updates had issues (check logs)"
        fi
    fi
    
    log_success "Application migration phase completed"
}

# Phase 5: Post-Migration Validation
run_post_migration_validation() {
    if [[ "$SKIP_POST_VALIDATION" == "true" ]]; then
        log_warning "Skipping post-migration validation"
        return 0
    fi
    
    log_phase "✅ Phase 5: Post-Migration Validation"
    
    cd "$SCRIPT_DIR/03-migration-scripts/phase5-verification"
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "TEST MODE: Would run post-migration validation"
        log "Command: ./run_test_suite.sh --mode=post-migration"
        return 0
    fi
    
    log "Running comprehensive post-migration validation..."
    if ../phase1-validation/run_test_suite.sh --mode=post-migration; then
        log_success "Post-migration validation completed successfully"
    else
        log_warning "Post-migration validation found issues (check logs)"
        log "Migration may have completed with warnings"
    fi
    
    # Display migration summary
    log_phase "📊 Migration Summary"
    
    # Count migrated users
    local user_count
    user_count=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                 "$DEST_API/users/api/users" | jq '. | length' 2>/dev/null || echo "N/A")
    log "Total users in destination: $user_count"
    
    # Count migrated teams
    local team_count
    team_count=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                 "$DEST_API/users/api/teams" | jq '. | length' 2>/dev/null || echo "N/A")
    log "Total teams in destination: $team_count"
    
    # Count environments
    local env_count
    env_count=$(curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
                "$DEST_API/environments/api/environments" | jq '. | length' 2>/dev/null || echo "N/A")
    log "Total environments in destination: $env_count"
    
    log "Migration logs available in: $SCRIPT_DIR/logs/"
}

# Selective migration mode
run_selective_migration() {
    log_phase "🎯 Selective Migration Mode"
    log "Choose which components to migrate:"
    
    echo "1) Environment Settings & Policies"
    echo "2) Users & Teams"
    echo "3) Applications"
    echo "4) All of the above"
    echo "5) Custom selection"
    
    read -p "Enter your choice (1-5): " choice
    
    case $choice in
        1)
            run_environment_migration
            ;;
        2)
            run_user_team_migration
            ;;
        3)
            run_application_migration
            ;;
        4)
            run_user_team_migration
            run_environment_migration
            run_application_migration
            ;;
        5)
            echo "Custom selection:"
            read -p "Migrate users & teams? (y/n): " user_choice
            read -p "Migrate environments? (y/n): " env_choice
            read -p "Migrate applications? (y/n): " app_choice
            
            [[ "$user_choice" =~ ^[Yy] ]] && run_user_team_migration
            [[ "$env_choice" =~ ^[Yy] ]] && run_environment_migration
            [[ "$app_choice" =~ ^[Yy] ]] && run_application_migration
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    log_phase "🚀 Starting Complete Cross-Environment Migration"
    
    # Check prerequisites
    check_prerequisites
    
    # Phase 1: Pre-Migration Validation
    run_pre_migration_validation
    
    # Run migration based on mode
    if [[ "$MIGRATION_MODE" == "selective" ]]; then
        run_selective_migration
    else
        # Phase 2: User & Team Migration
        run_user_team_migration
        
        # Phase 3: Environment Migration
        run_environment_migration
        
        # Phase 4: Application Migration
        run_application_migration
    fi
    
    # Phase 5: Post-Migration Validation
    run_post_migration_validation
    
    # Final success message
    log_phase "🎉 Migration Workflow Completed!"
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log_success "Test mode completed successfully"
        log "No actual changes were made to the environments"
    else
        log_success "Cross-environment migration completed successfully!"
        log "Please verify the results in the destination Nirmata UI"
    fi
    
    log "Migration logs are available in: $SCRIPT_DIR/logs/"
    log "For detailed results, check the individual log files"
    
    # Display next steps
    echo -e "\n${BLUE}📋 Next Steps:${NC}"
    echo "1. Review migration logs for any warnings or issues"
    echo "2. Verify migrated users, teams, and environments in destination UI"
    echo "3. Test application deployments using migrated catalog applications"
    echo "4. Update any external references to point to new environment"
    echo "5. Communicate migration completion to relevant stakeholders"
}

# Trap to handle script interruption
trap 'log_error "Migration interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"