# 🚀 Enhanced Environment to Catalog Migration

## Overview
Enterprise-grade migration script with **production-ready naming** that creates clean, cluster-agnostic catalog applications for seamless cluster-to-cluster migrations.

## 🎯 Production-Ready Features

### ✅ **Clean Naming Convention**
- **NO old cluster references** in catalog app names
- Example: `conformance-132-shuting` → `shuting` (NOT `app-shuting-conformance-132`)
- Forward-looking, professional naming for production use
- Intelligent conflict resolution with versioning

### ✅ **Safety-First Design**
- **Dry run by default** - Preview changes before making them
- Confirmation prompts for live execution
- Comprehensive logging with detailed and summary logs
- Mode indicators throughout (🔍 DRY RUN vs 🚀 LIVE)

### ✅ **Enterprise Features**
- **🎯 Interactive Mode** with y/n/list/skip confirmations for each environment
- **👥 Automatic Team Permissions** - copies team permissions from source environments to catalog level
- **📋 Mapping Preview** - shows applications and permissions before migration
- Verbose mode for detailed API debugging
- Auto-confirm mode for scripted execution
- Smart Git credential mapping with fallback strategies
- Enhanced error handling and authentication validation

## 🔧 Quick Start

### Step 1: Preview Migration (Safe)
```bash
# Default dry run mode - no changes made
./migrate_env_apps_to_catalog.sh \
  https://your-nirmata-endpoint.com \
  "YOUR_API_TOKEN" \
  "source-cluster" \
  "destination-cluster"
```

### Step 2: Execute Migration (Interactive Mode)
```bash
# Live execution with interactive y/n/list/skip confirmations
./migrate_env_apps_to_catalog.sh \
  https://your-nirmata-endpoint.com \
  "YOUR_API_TOKEN" \
  "source-cluster" \
  "destination-cluster" \
  --live

# Interactive session shows:
# - Applications to migrate
# - Team permissions to copy
# - Catalog mapping options
# - y/n/list/skip choices
```

### Step 3: Automated Execution
```bash
# Automated mode for scripts (use with caution)
./migrate_env_apps_to_catalog.sh \
  https://your-nirmata-endpoint.com \
  "YOUR_API_TOKEN" \
  "source-cluster" \
  "destination-cluster" \
  --live --auto-confirm
```

## 🎯 Production Naming Examples

| Environment | Application | OLD Naming (BAD) | NEW Naming (GOOD) |
|-------------|-------------|------------------|-------------------|
| `conformance-132-shuting` | `shuting` | `app-shuting-conformance-132` | `shuting` |
| `satya-conformance-132` | `monitoring` | `app-monitoring-conformance-132` | `monitoring` |
| `prod-user-service` | `user-service` | `app-user-service-conformance-132` | `user-service` |

**See [PRODUCTION_NAMING_EXAMPLES.md](PRODUCTION_NAMING_EXAMPLES.md) for complete naming strategy documentation.**

## 📋 Complete Options

```bash
Usage: migrate_env_apps_to_catalog.sh <endpoint> <token> <source> <dest> [OPTIONS]

OPTIONS:
  --dry-run          Preview migration (DEFAULT)
  --live             Execute actual migration
  --auto-confirm     Skip confirmation prompts (no interactive mode)
  --verbose          Detailed API logging
  --help             Show complete help
```

## 🎯 Interactive Mode Features

### **Environment-by-Environment Confirmation**
For each environment with Git-based applications:
- Shows **applications to migrate**
- Shows **team permissions to copy**
- Provides **catalog mapping options**
- Interactive **y/n/list/skip** choices

### **Available Options**
- **`y` (yes)**: Confirm migration with suggested catalog name
- **`n` (no)**: Reject and specify custom catalog name  
- **`list`**: Show all available catalogs
- **`skip`**: Skip this environment completely

### **Example Interactive Session**
```
🔍 ENVIRONMENT → CATALOG MAPPING CONFIRMATION
==============================================
Source Environment: conformance-132-shuting
Suggested Catalog: conformance

📱 Git-based applications to migrate (1):
  - shuting

👥 Team permissions to copy to catalog:
  - new-migration-team → view
  - vikash-team → view

Do you want to migrate applications from 'conformance-132-shuting' to catalog 'conformance'? (y/n/list/skip): y
✅ Confirmed: conformance-132-shuting → conformance
```

## 👥 Team Permissions Management

### **Automatic Team Permission Copy**
- **Detects team permissions** in source environments
- **Copies to catalog level** (not individual applications)
- **Maintains permission levels** (view, edit, admin)
- **Applies to entire catalog** - teams get access to ALL applications

### **Benefits**
- **Security Preserved**: Teams maintain their access levels
- **Simplified Management**: Catalog-level permissions vs per-app
- **Automatic Detection**: No manual configuration required
- **Safe Migration**: Existing access controls preserved

### **Permission Flow**
```
Source Environment (conformance-132-shuting)
├── Team: dev-team (view)
├── Team: ops-team (edit)
└── Team: admin-team (admin)

Target Catalog (conformance)
├── Team: dev-team (view) ✅ COPIED
├── Team: ops-team (edit) ✅ COPIED
└── Team: admin-team (admin) ✅ COPIED
```

## 🛡️ Safety Features

### 🔍 **Dry Run Mode (Default)**
- Preview all changes before execution
- No API modifications made
- Comprehensive logging for review
- Perfect for validation and planning

### 🚀 **Live Mode**
- Confirmation prompts before execution
- Real-time progress updates
- Detailed success/failure reporting
- Rollback information preserved

### 🤖 **Auto-Confirm Mode**
- Automated execution for CI/CD pipelines
- Skip interactive prompts
- Comprehensive logging maintained
- Use with extreme caution in production

## 📊 Logging System

All operations are logged to `./logs/` directory:

- **Detailed Log**: `migration_detailed_SOURCE_to_DEST_TIMESTAMP.log`
- **Summary Log**: `migration_summary_SOURCE_to_DEST_TIMESTAMP.log`
- **Team Permissions**: Shows team permission detection and catalog application
- **Mode Indicators**: 🔍 DRY RUN vs 🚀 LIVE clearly marked

## 🔧 Advanced Features

### **Intelligent Git Credential Mapping**
- Automatic credential matching by name
- Fallback to first available credential
- Comprehensive validation and error handling

### **Conflict Resolution**
- Automatic detection of existing applications
- Version-based naming for conflicts (e.g., `app-name-v2`)
- Timestamp fallbacks for edge cases

### **Enhanced Error Handling**
- Authentication validation
- Cluster existence verification
- Git repository accessibility checks
- Comprehensive error reporting

## 🎯 Migration Workflow

1. **Validation**: Authenticate and validate clusters
2. **Discovery**: Find environments and Git-based applications
3. **Team Detection**: Identify team permissions in source environments
4. **Interactive Confirmation**: y/n/list/skip choices for each environment
5. **Mapping**: Intelligent credential and naming mapping
6. **Preview**: Show what will be migrated (dry run)
7. **Execution**: Create catalog applications (live mode)
8. **Permissions**: Apply team permissions to catalog level
9. **Reporting**: Comprehensive success/failure summary

## 🔒 Production Considerations

### **Pre-Migration Checklist**
- [ ] Backup source environment configurations
- [ ] Verify destination cluster catalog access
- [ ] Test with dry run mode first
- [ ] Validate Git credential availability
- [ ] Review naming convention requirements
- [ ] Verify team permissions in source environments
- [ ] Confirm catalog-level permission requirements

### **Post-Migration Steps**
- [ ] Verify catalog applications created successfully
- [ ] Verify team permissions applied to catalog level
- [ ] Test application deployment in destination cluster
- [ ] Test team access to catalog applications
- [ ] Update CI/CD pipelines with new catalog references
- [ ] Archive or cleanup source environment applications 