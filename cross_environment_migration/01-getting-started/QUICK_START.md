# 🚀 Quick Start Guide

## Prerequisites Completed ✅
- All required tools are installed
- Directory structure is set up
- Scripts are executable
- Configuration template is ready

## Next Steps

### 1. Configure Your Migration
```bash
# Go to configuration directory
cd ../02-configuration

# Edit the configuration file with your environment details
nano migration_config.sh

# Or copy and customize the template
cp migration_config_template.sh my_migration_config.sh
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

#### Option A: Phase-by-Phase Migration (Recommended)
```bash
# Phase 1: Pre-migration validation
cd ../03-migration-scripts/phase1-validation
./RUN_THIS_PHASE.sh

# Phase 2: User & team migration
cd ../phase2-users-teams
./RUN_THIS_PHASE.sh

# Phase 3: Environment migration
cd ../phase3-environments
./RUN_THIS_PHASE.sh

# Phase 4: Application migration
cd ../phase4-applications
./RUN_THIS_PHASE.sh

# Phase 5: Post-migration validation
cd ../phase5-verification
./RUN_THIS_PHASE.sh
```

#### Option B: Complete Migration (Alternative)
```bash
# Run full migration workflow
cd ../..
./complete_migration_workflow.sh

# Or with custom config
./complete_migration_workflow.sh --config 02-configuration/my_migration_config.sh

# Test mode (dry run)
./complete_migration_workflow.sh --test
```

### 4. Verify Results
- Check logs in `06-logs/` directory
- Verify in destination Nirmata UI
- Test application deployments
- Test user logins (especially SAML/Azure AD users)

## ✨ Benefits of Phase-by-Phase Approach

- **🔍 Full Control**: Inspect results after each phase
- **🛡️ Safety**: Stop and fix issues before proceeding
- **📊 Visibility**: Clear feedback and troubleshooting for each phase
- **🔄 Flexibility**: Re-run individual phases if needed
- **📋 Simplicity**: No complex parameter passing - everything is automated

## Need Help?
- Check the comprehensive README.md in `01-getting-started/`
- Review phase-specific documentation in `03-migration-scripts/phase*/`
- Check troubleshooting guides in `05-documentation/`
- Review migration logs in `06-logs/` for detailed information
