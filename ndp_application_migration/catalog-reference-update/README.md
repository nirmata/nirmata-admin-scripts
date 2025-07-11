# Catalog Reference Update Scripts

This directory contains advanced scripts for updating catalog references for applications in Nirmata environments after Velero-based migrations or cross-cluster operations. The scripts provide robust error handling, interactive features, and comprehensive pattern matching.

## 🚀 Scripts Available

### 1. `update_catalog_references_fixed_api.sh` (Recommended)
- **Main script** with enhanced interactive features
- **Fixed API method** for persistent catalog references
- **Comprehensive pattern matching** with fallback options
- **Dynamic catalog listing** from live API
- **Progress indicators** and real-time feedback

### 2. `update_catalog_references_cross_env_mapping.sh`
- **Cross-environment mapping** for Velero restore scenarios
- **Namespace-based mapping** logic
- **Source-to-destination environment mapping**

## ✨ Key Features

### 🔧 **Enhanced API Integration**
- ✅ **Robust error handling** using patterns from `restore_env_settings.sh`
- ✅ **Safe JSON parsing** with fallback mechanisms
- ✅ **Rate limiting protection** with exponential backoff
- ✅ **Authentication validation** with clear error messages
- ✅ **Timeout protection** (5-minute interactive timeout)

### 🎯 **Interactive Mode**
- ✅ **y/n/list/skip options** for complete control
- ✅ **Dynamic catalog listing** - shows ALL available catalog applications from API
- ✅ **Manual catalog selection** when auto-detection fails
- ✅ **Real-time validation** of user inputs
- ✅ **Skip problematic applications** without stopping the process

### 📊 **Progress Tracking**
- ✅ **Environment progress**: `🔍 [6/19] Processing environment: env-name`
- ✅ **Application progress**: `[1/3] 🔧 Processing app: app-name`
- ✅ **Real-time status updates** for all operations
- ✅ **Comprehensive logging** with timestamps

### 🧠 **Smart Pattern Matching**
- ✅ **Exact name matching**
- ✅ **Cluster prefix/suffix removal** (e.g., `app-cluster-name` → `app`)
- ✅ **Version suffix removal** (e.g., `app-v1` → `app`)
- ✅ **Timestamp removal** (e.g., `app-20250710123456` → `app`)
- ✅ **Case-insensitive matching**
- ✅ **Fuzzy matching** as fallback
- ✅ **Prefix pattern removal** (e.g., `app-` prefix)

## 📋 Prerequisites

- Bash shell environment
- `curl` command-line tool
- `jq` JSON processor (v1.6+)
- Valid Nirmata API access token
- Source and destination cluster access

## 🚀 Usage

### Main Script (Recommended)

```bash
./update_catalog_references_fixed_api.sh <api_endpoint> <token> <source_cluster> <destination_cluster> [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be done without making changes (DEFAULT) |
| `--interactive` | Review and confirm each mapping before applying |
| `--auto` | Run automatically without prompts |

### Examples

#### 1. **Interactive Mode (Recommended)**
```bash
./update_catalog_references_fixed_api.sh https://staging.nirmata.co 'YOUR_TOKEN' 'conformance-132' 'another-rhel9' --interactive
```

#### 2. **Dry Run Preview**
```bash
./update_catalog_references_fixed_api.sh https://staging.nirmata.co 'YOUR_TOKEN' 'conformance-132' 'another-rhel9' --dry-run
```

#### 3. **Automatic Mode**
```bash
./update_catalog_references_fixed_api.sh https://staging.nirmata.co 'YOUR_TOKEN' 'conformance-132' 'another-rhel9' --auto
```

### Cross-Environment Mapping (Velero Scenarios)

```bash
./update_catalog_references_cross_env_mapping.sh https://staging.nirmata.co 'YOUR_TOKEN' 'source-cluster' 'dest-cluster' --interactive
```

## 🎯 Interactive Experience

When using `--interactive` mode, you'll see:

```
🔍 [4/19] Processing environment: nirmata-another-rhel9
   📱 Found 1 applications in this environment
      [1/1] 🔧 Processing app: nirmata

🔍 APPLICATION: nirmata (Environment: nirmata-another-rhel9)
No automatic catalog match found.

Available catalog applications:
  - best-practices
  - dolis-git
  - gitlab-madhu-ngnx
  - kyverno
  - new-nginx
  - nginx-ingress
  - prometheus
  ... (95+ total applications)

Enter catalog application name for 'nirmata' (or 'skip' to skip): kyverno
✅ Mapping confirmed: nirmata → kyverno
```

### Interactive Options

| Input | Action |
|-------|--------|
| `kyverno` | Map application to 'kyverno' catalog |
| `skip` | Skip this application |
| `[Enter]` | Skip (empty input) |
| ⏰ *Timeout* | Auto-skip after 5 minutes |

## 📊 Output and Logging

### Real-time Output
```
🔧 FIXED Catalog Reference Update (Proper API Method)
[2025-07-11 13:53:22] [🎯 INTERACTIVE] Authentication successful
[2025-07-11 13:53:22] [🎯 INTERACTIVE] Found 19 environments in destination cluster

🔍 [1/19] Processing environment: default-another-rhel9
   ℹ️  No applications found in environment: default-another-rhel9

🔍 [6/19] Processing environment: another-rhel9-ritu-nginx
   📱 Found 1 applications in this environment
      [1/1] 🔧 Processing app: ritu-nginx
   🔗 Manual mapping: ritu-nginx → new-nginx
   ✅ Mapping confirmed: ritu-nginx → new-nginx
```

### Final Summary
```
========================================
🔧 FINAL SUMMARY (Fixed API Method)
========================================
Linked applications: 2
Fixed wrong references: 1
Failed operations: 0
Total processed: 3
========================================
```

### Log Files
- **Location**: `logs/` directory
- **Format**: `catalog_reference_fixed_CLUSTER_to_CLUSTER_TIMESTAMP.log`
- **Content**: Detailed API calls, responses, errors, and decisions

## 🛡️ Error Handling

### Authentication Errors
```
[ERROR] Authentication failed. HTTP code: 401
Please check your token and permissions.
```

### API Rate Limiting
```
Rate limited, waiting 15 seconds before retry...
```

### Invalid Catalog Selection
```
❌ Catalog 'invalid-name' not found. Skipping app-name
Available catalogs: [shows current list]
```

### JSON Parsing Errors
- **Automatic fallback** to safe defaults
- **Error suppression** with `/dev/null` redirection
- **Graceful degradation** when APIs return unexpected data

## 🔍 Troubleshooting

### Script Hangs at Interactive Prompt
✅ **Fixed**: 5-minute timeout protection automatically skips

### No Catalog Applications Listed
- ✅ **Fixed**: Dynamic API retrieval shows 95+ real catalog apps
- ✅ **Fallback**: Shows error message if API fails

### JSON Parsing Errors
- ✅ **Fixed**: Robust error handling prevents crashes
- ✅ **Safe extraction**: All JSON operations use error-safe methods

### Authentication Issues
1. Verify API token format and validity
2. Check token permissions for environments and catalog APIs
3. Ensure correct API endpoint URL

### Missing Environment Applications
- Script automatically handles empty environments
- Logs show clear "No applications found" messages
- Continues processing remaining environments

## 📈 Performance Optimizations

- **Efficient API calls**: Batch operations where possible
- **Progress feedback**: Real-time status without overwhelming output
- **Smart caching**: Catalog applications retrieved once per run
- **Parallel-safe**: Handles multiple concurrent operations safely

## 🔧 Advanced Usage

### Custom Pattern Matching
The script automatically tries these patterns in order:
1. **Exact match**: `app-name` → `app-name`
2. **Cluster removal**: `app-name-cluster` → `app-name`  
3. **Version removal**: `app-name-v1` → `app-name`
4. **Timestamp removal**: `app-name-20250710` → `app-name`
5. **Prefix removal**: `app-app-name` → `app-name`
6. **Fuzzy matching**: Contains substring
7. **Interactive fallback**: Manual selection

### Validation and Verification
- **Pre-flight checks**: Validates clusters and authentication
- **Real-time verification**: Confirms each catalog reference update
- **Post-update validation**: Ensures changes were applied correctly

## 🆘 Support

### Log Analysis
```bash
# View latest log
cat logs/catalog_reference_fixed_*_$(date +%Y%m%d)*.log | tail -50

# Check for errors
grep "ERROR" logs/catalog_reference_fixed_*.log

# View summary
grep "FINAL SUMMARY" logs/catalog_reference_fixed_*.log
```

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| Script hangs | ✅ **Fixed**: Automatic timeout protection |
| Missing catalogs | ✅ **Fixed**: Dynamic API retrieval |
| JSON errors | ✅ **Fixed**: Robust error handling |
| Auth failures | Check token and permissions |
| API rate limits | ✅ **Fixed**: Automatic retry with backoff |

For additional support, provide:
1. **Log file** from the `logs/` directory
2. **Error message** from console output
3. **API endpoint** and cluster names used
4. **Script version** and parameters used

---

## 🎉 Recent Improvements (v2.0)

- ✅ **Interactive mode** with y/n/list/skip options  
- ✅ **Dynamic catalog listing** from live API
- ✅ **Enhanced error handling** using production patterns
- ✅ **Progress indicators** for better UX
- ✅ **Timeout protection** prevents hanging
- ✅ **Safe JSON parsing** with fallback mechanisms
- ✅ **Real-time feedback** during operations
- ✅ **Comprehensive pattern matching** for auto-detection
- ✅ **Cross-environment support** for Velero scenarios 