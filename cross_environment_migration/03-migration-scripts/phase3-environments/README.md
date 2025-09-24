# 🏗️ Phase 3: Environment Migration & Settings Restoration

**Purpose**: Comprehensive migration of environment settings, configurations, and access controls between Nirmata clusters

## 🚀 Enhanced Features

### 🎯 **`restore_env_settings_cross_env.sh` - The Powerhouse Script**

This script has been completely enhanced to provide enterprise-grade environment migration with:

- **🛡️ System Namespace Filtering**: Automatically skips system namespaces
- **🤝 Interactive Mode**: Manual confirmation of each environment mapping
- **📋 Comprehensive Settings Copy**: All environment configurations, not just teams
- **🔍 Intelligent Mapping**: Smart pattern matching for environment names
- **📊 Detailed Logging**: Complete audit trail with timestamped entries
- **⚡ Multiple Safety Modes**: Dry-run, interactive, and automated options

## 🔧 What Gets Migrated (Complete List)

### 📦 **Environment Settings**
- **Resource Quotas**: CPU, memory, storage limits
- **Limit Ranges**: Container resource constraints
- **Access Controls**: Teams, users, roles, and permissions
- **Labels & Metadata**: Environment tags and descriptions
- **Owner Details**: Created by, modified by information
- **Update Policies**: Environment update configurations
- **Kubernetes Resources**: ConfigMaps, Secrets, RoleBindings, etc.

### 🛡️ **System Namespaces Automatically Skipped**
- `nirmata`, `nirmata-system`
- `kyverno`, `kyverno-system`
- `ingress-haproxy`, `ingress-nginx`
- `kube-system`, `kube-public`, `kube-node-lease`
- `default`, `cert-manager`, `monitoring`, `logging`

## 🎮 Usage Modes

### 1. 🔍 **DRY-RUN Mode (Recommended First)**
```bash
cd 03-migration-scripts/phase3-environments
./restore_env_settings_cross_env.sh \
  https://staging.nirmata.co SOURCE_TOKEN conformance-132 \
  https://pe420.nirmata.co DEST_TOKEN old-app-migration \
  --dry-run
```
- **Safe preview** of what would be done
- **No changes** made to destination
- **Environment mapping** preview generated
- **Log files** created for review

### 2. 🤝 **Interactive Mode (Recommended)**
```bash
cd 03-migration-scripts/phase3-environments
./restore_env_settings_cross_env.sh \
  https://staging.nirmata.co SOURCE_TOKEN conformance-132 \
  https://pe420.nirmata.co DEST_TOKEN old-app-migration \
  --interactive --live
```
- **Manual confirmation** of each environment mapping
- **1:1 mapping display** before execution
- **Skip or customize** any environment mapping
- **Complete control** over what gets migrated

### 3. 🤖 **Automated Mode (Advanced)**
```bash
cd 03-migration-scripts/phase3-environments
./restore_env_settings_cross_env.sh \
  https://staging.nirmata.co SOURCE_TOKEN conformance-132 \
  https://pe420.nirmata.co DEST_TOKEN old-app-migration \
  --live --auto-confirm
```
- **Fully automated** execution
- **No prompts** - processes all detected mappings
- **Use with caution** - only after dry-run verification

### 4. 📋 **Mapping File Mode (Ultra-Safe)**
```bash
cd 03-migration-scripts/phase3-environments

# Step 1: Generate mapping file
./restore_env_settings_cross_env.sh \
  https://staging.nirmata.co SOURCE_TOKEN conformance-132 \
  https://pe420.nirmata.co DEST_TOKEN old-app-migration \
  --generate-mapping

# Step 2: Review and edit the generated mapping file
# Edit: logs/env_mapping_preview_DRY_RUN_YYYYMMDD_HHMMSS.json

# Step 3: Execute with verified mapping
./restore_env_settings_cross_env.sh \
  https://staging.nirmata.co SOURCE_TOKEN conformance-132 \
  https://pe420.nirmata.co DEST_TOKEN old-app-migration \
  --use-mapping-file verified_mapping.json --live
```

## 🎯 Smart Environment Mapping

The script intelligently maps environments using multiple strategies:

### 📍 **Pattern Matching Examples**
- `mukesh-conformance-132` → `mukesh-old-app-migration`
- `conformance-132-shuting` → `shuting-old-app-migration`
- `destiny` → `destiny-old-app-migration`
- `velero-conformance-132` → `velero-123-app-migration`

### 🔍 **Mapping Strategies**
1. **Exact Match**: Direct name matching
2. **Cluster Pattern**: Remove/replace cluster names
3. **Namespace Extraction**: Extract core namespace name
4. **Fuzzy Matching**: Contains-based matching
5. **Custom Mapping**: Manual specification in interactive mode

## 📊 Comprehensive Logging

### 📁 **Generated Files**
```
logs/
├── env_restore_LIVE_INTERACTIVE_20250702_095057.log     # Detailed operations log
├── env_restore_summary_LIVE_INTERACTIVE_20250702_095057.log  # Summary log
└── env_mapping_confirmed_LIVE_INTERACTIVE_20250702_095057.json  # Mapping file
```

### 📝 **Log Contents**
- **🕒 Timestamped entries** for complete audit trail
- **🔍 DRY-RUN prefix** for safe mode operations
- **🚀 LIVE mode** records all actual API calls
- **❌ Error details** for troubleshooting
- **📊 Success/failure counts** for each operation

## 🎭 Interactive Mode Experience

### 🔍 **Environment Confirmation**
```
🔍 ENVIRONMENT MAPPING CONFIRMATION
======================================
Source Environment: mukesh-conformance-132
Suggested Destination: mukesh-old-app-migration

Do you want to copy settings from 'mukesh-conformance-132' to 'mukesh-old-app-migration'? (y/n/list): y
✅ Confirmed: mukesh-conformance-132 → mukesh-old-app-migration
```

### 📋 **Final Confirmation Display**
```
📋 CONFIRMED 1:1 ENVIRONMENT MAPPINGS:
======================================
 1. mukesh-conformance-132           → mukesh-old-app-migration
 2. baba-conformance-132             → baba-old-app-migration
 3. satya-conformance-132            → satya-old-app-migration
 4. conformance-132-shuting          → shuting-old-app-migration
 5. destiny                          → destiny-old-app-migration
 6. velero-conformance-132           → velero-123-app-migration

⚠️  WARNING: This will make LIVE CHANGES to destination environment!
🔧 Settings to be copied for EACH environment above:
   • Resource Quotas & Limit Ranges
   • Access Controls (Teams, Users, Roles)
   • Labels & Owner Details
   • Update Policies
   • Kubernetes Resources (ConfigMaps, Secrets, etc.)

Proceed with copying settings for the 6 confirmed mappings? (y/N):
```

## 🔒 Safety Features

### 🛡️ **Multiple Safety Layers**
1. **DRY-RUN Default**: Safe preview mode by default
2. **Interactive Confirmation**: Manual approval of each mapping
3. **System Namespace Protection**: Automatic filtering of system namespaces
4. **Mapping File Verification**: Pre-verified mapping file support
5. **Comprehensive Logging**: Complete audit trail
6. **Error Handling**: Graceful failure with detailed error messages

### ⚠️ **Safety Requirements**
- **Live mode requires** one of: `--auto-confirm`, `--interactive`, or `--use-mapping-file`
- **No accidental execution** without explicit confirmation
- **System namespaces protected** from accidental modification

## 📋 Prerequisites

### ✅ **Required**
- **Phase 2 completed**: Teams must exist in destination cluster
- **Valid API tokens** for both source and destination
- **Cluster access** with environment management permissions
- **Network connectivity** to both Nirmata instances

### 🔍 **Verification Commands**
```bash
# Verify source cluster access
curl -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
  "$SOURCE_API_ENDPOINT/environments/api/clusters"

# Verify destination cluster access  
curl -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API_ENDPOINT/environments/api/clusters"
```

## 📊 Expected Output

### ✅ **Successful Execution**
```
🚀 Starting LIVE environment processing...
🤝 Processing 6 interactively confirmed environment mappings...

[2025-07-02 09:51:57] Processing source environment: mukesh-conformance-132
[2025-07-02 09:51:57] Found destination environment: mukesh-old-app-migration (ID: abc123)
[2025-07-02 09:51:57] Copying ALL environment settings...
[2025-07-02 09:51:58] Copying resource quotas...
[2025-07-02 09:51:59] Copying limit ranges...
[2025-07-02 09:52:00] Copying access controls from ACL: def456
[2025-07-02 09:52:01] Successfully created ACL for team new-migration-team
[2025-07-02 09:52:02] Successfully copied settings from mukesh-conformance-132 to mukesh-old-app-migration

📊 FINAL SUMMARY:
Total environments processed: 6
Successful copies: 6
Skipped environments: 0
Failed copies: 0

✅ LIVE migration completed successfully! All settings have been copied.
```

### 📁 **Output Files**
```
📁 OUTPUT FILES GENERATED:
  📋 Detailed Log: logs/env_restore_LIVE_INTERACTIVE_20250702_095057.log
  📊 Summary Log: logs/env_restore_summary_LIVE_INTERACTIVE_20250702_095057.log
  🗺️  Environment Mappings: logs/env_mapping_confirmed_LIVE_INTERACTIVE_20250702_095057.json

💡 LOG FILE CONTENTS:
  🚀 LIVE mode - All actual operations and API calls logged
  📝 Complete record of all environment settings copied
  🕒 Timestamped entries for audit trail
  ❌ Error details for troubleshooting
```

## 🚨 Troubleshooting

### ❌ **Common Issues**

#### 1. **Team Not Found Warnings**
```
WARNING: Team new-migration-team not found in destination cluster - skipping ACL creation
```
**Solution**: Ensure Phase 2 (Users & Teams) was completed successfully

#### 2. **Environment Mapping Issues**
```
❌ mukesh-conformance-132 -> NO MATCH FOUND
```
**Solution**: Use `--interactive` mode to manually specify correct mapping

#### 3. **API Authentication Errors**
```
ERROR: Source environment authentication failed. HTTP code: 401
```
**Solution**: Verify API tokens are valid and have required permissions

#### 4. **Resource Creation Failures**
```
WARNING: Failed to create quota memory-quota
```
**Solution**: Check destination cluster resource limits and permissions

### 🔧 **Debug Commands**
```bash
# Check authentication
curl -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/clusters"

# List environments in cluster
curl -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/environments/api/environments" | \
  jq '.[] | select(.cluster[].name == "CLUSTER_NAME") | .name'

# Check team existence
curl -H "Authorization: NIRMATA-API $TOKEN" "$API_ENDPOINT/users/api/teams" | \
  jq '.[] | .name'
```

## 🎯 Best Practices

### 📋 **Recommended Workflow**
1. **🔍 Start with dry-run**: `--dry-run` to preview mappings
2. **📝 Review logs**: Check generated mapping file
3. **🤝 Use interactive mode**: `--interactive --live` for controlled execution
4. **📊 Verify results**: Check destination environments post-migration
5. **🔄 Iterate if needed**: Re-run with corrections for any failures

### 🛡️ **Safety Best Practices**
- **Always dry-run first** before live execution
- **Use interactive mode** for critical migrations
- **Review mapping files** before automated execution
- **Keep logs** for audit and troubleshooting
- **Test with non-critical environments** first

## 📋 Next Steps

After Phase 3 completes successfully:
- **✅ Verify**: All environments created with correct settings
- **🔍 Check**: Team permissions properly assigned
- **📊 Review**: Logs for any warnings or issues
- **➡️ Proceed**: To Phase 4 (Applications) migration

**Phase 4**: `../phase4-applications/` - Application and catalog migration 