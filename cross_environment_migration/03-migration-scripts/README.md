# 🚀 Migration Scripts - 5-Phase Approach

This directory contains all migration scripts organized by the **5-phase migration workflow**. Each phase must be completed in order for successful migration.

## 📋 Migration Flow

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5
   ↓         ↓         ↓         ↓         ↓
Validate  Envs     Users     Apps      Verify
```

## 📁 Phase Directories

### 📋 **Phase 1: Validation** (`phase1-validation/`)
**Purpose**: Pre-migration validation and compatibility testing
- `run_test_suite.sh` - Comprehensive pre-migration tests
- `test_identity_provider_compatibility.sh` - Identity provider compatibility check
- `simulate_perfect_migration.sh` - Dry run simulation

**When to use**: Before starting any migration to ensure environments are ready

### 🏗️ **Phase 2: Environments** (`phase2-environments/`)
**Purpose**: Migrate environment settings, policies, and team permissions
- `restore_env_settings_cross_env.sh` - Complete environment migration

**What it migrates**:
- Environment configurations
- Team role bindings
- Policies and settings
- Environment metadata

### 👥 **Phase 3: Users & Teams** (`phase3-users-teams/`)
**Purpose**: Migrate users and teams with role preservation
- `copy_cluster_teams_with_full_user_roles.sh` - Complete user/team migration
- `copy_cluster_teams_with_roles.sh` - Alternative team migration

**What it migrates**:
- User profiles with roles (admin, devops, etc.)
- Identity providers (SAML, Azure AD, Local)
- Team structures and memberships
- User-team associations

### 📱 **Phase 4: Applications** (`phase4-applications/`)
**Purpose**: Migrate applications from Git-based to catalog-based
- `migrate_env_apps_to_catalog_cross_env.sh` - Convert apps to catalog
- `update_catalog_references_cross_env.sh` - Update application references

**What it migrates**:
- Git-based applications → Catalog applications
- Application configurations
- Git credentials mapping
- Environment references

### ✅ **Phase 5: Verification** (`phase5-verification/`)
**Purpose**: Post-migration validation and testing
- `run_test_suite.sh` - Post-migration validation tests

**What it validates**:
- User and team migration success
- Role preservation accuracy
- Environment configuration integrity
- Application functionality

## 🎯 **Usage Patterns**

### **Option 1: Run Individual Phases** (Recommended)
**This is the preferred approach for production environments**
```bash
# Phase 1: Validation
./03-migration-scripts/phase1-validation/run_test_suite.sh

# Phase 2: Environments
./03-migration-scripts/phase2-environments/restore_env_settings_cross_env.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"

# Phase 3: Users & Teams
./03-migration-scripts/phase3-users-teams/copy_cluster_teams_with_full_user_roles.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"

# Phase 4a: Applications
./03-migration-scripts/phase4-applications/migrate_env_apps_to_catalog_cross_env.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"

# Phase 4b: References
./03-migration-scripts/phase4-applications/update_catalog_references_cross_env.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"

# Phase 5: Verification
./03-migration-scripts/phase5-verification/run_test_suite.sh
```

### **Option 2: Use Complete Workflow** (Alternative)
```bash
# Run all phases automatically
./complete_migration_workflow.sh
```

### **Option 3: Selective Migration**
```bash
# Run only specific phases as needed
./complete_migration_workflow.sh --mode selective
```

## ⚠️ **Important Notes**

### **Phase Dependencies**
- Phase 2 (Environments) must complete before Phase 3 (Users)
- Phase 3 (Users) must complete before Phase 4 (Applications)
- Phase 1 (Validation) should always run first
- Phase 5 (Verification) should always run last

### **Error Handling**
- If any phase fails, fix issues before proceeding to next phase
- Check logs in `06-logs/` directory for detailed error information
- Use test mode (`--test`) to validate without making changes

### **Configuration**
- All scripts require the same configuration parameters
- Load configuration: `source 02-configuration/migration_config.sh`
- See `04-examples/` for usage examples

## 📊 **Expected Outcomes**

| Phase | Success Indicator | Typical Duration |
|-------|------------------|------------------|
| 1 | All tests pass | 2-5 minutes |
| 2 | Environments copied | 5-15 minutes |
| 3 | Users/teams migrated | 10-30 minutes |
| 4 | Applications catalogized | 15-60 minutes |
| 5 | Validation passes | 5-10 minutes |

**Total Migration Time**: 30-120 minutes (depending on data volume)

## 🆘 **Need Help?**

- Check `01-getting-started/README.md` for setup instructions
- Review `05-documentation/` for detailed guides
- See `04-examples/` for usage examples
- Check `06-logs/` for detailed operation logs 