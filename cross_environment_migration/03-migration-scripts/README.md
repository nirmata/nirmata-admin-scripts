# 🚀 Migration Scripts - 5-Phase Approach

## 📋 **MIGRATION PHASES**

### **Phase 1: Validation** 📋
**Location:** `phase1-validation/`
- Pre-migration validation and testing
- Identity provider compatibility checks
- Connection testing to both environments
- **Run:** `cd phase1-validation && ./RUN_THIS_PHASE.sh`

### **Phase 2: Users & Teams** 👥
**Location:** `phase2-users-teams/`
- Migrates all users with proper identity provider settings
- Creates all teams with correct permissions
- **Run:** `cd phase2-users-teams && ./RUN_THIS_PHASE.sh`

### **Phase 3: Environments** 🏗️
**Location:** `phase3-environments/`
- Restores environment settings and configurations
- Associates teams with proper environment permissions
- **Run:** `cd phase3-environments && ./RUN_THIS_PHASE.sh`

### **Phase 4: Applications** 📱
**Location:** `phase4-applications/`
- Migrates applications from environments to catalog
- Updates catalog references across applications
- **Run:** `cd phase4-applications && ./RUN_THIS_PHASE.sh`

### **Phase 5: Verification** ✅
**Location:** `phase5-verification/`
- Post-migration validation and testing
- Verifies all components migrated successfully
- **Run:** `cd phase5-verification && ./RUN_THIS_PHASE.sh`



## 🎯 **RECOMMENDED EXECUTION**

### **One-by-One Approach** (Recommended for Production)
```bash
cd 03-migration-scripts/phase1-validation && ./RUN_THIS_PHASE.sh
cd ../phase2-users-teams && ./RUN_THIS_PHASE.sh
cd ../phase3-environments && ./RUN_THIS_PHASE.sh
cd ../phase4-applications && ./RUN_THIS_PHASE.sh
cd ../phase5-verification && ./RUN_THIS_PHASE.sh
```

### **Full Automation** (Use with caution)
```bash
cd ../../ && ./complete_migration_workflow.sh
```

## 📝 **PHASE DEPENDENCIES**

- **Phase 1** → No dependencies
- **Phase 2** → Requires Phase 1 validation
- **Phase 3** → Requires Phase 2
- **Phase 4** → Requires Phase 3 (environments must exist)
- **Phase 5** → Requires all previous phases

## 🔍 **VERIFICATION**

After each phase, check the logs for successful completion:
```bash
# Check phase completion
ls -la 06-logs/phase*_*.log

# View latest logs
tail -n 20 06-logs/phase*_*.log
```

## 🆘 **TROUBLESHOOTING**

If any phase fails:
1. Check the corresponding log file in `06-logs/`
2. Verify API connectivity and tokens
3. Ensure source environment has the expected resources
4. Re-run the failed phase after resolving issues

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