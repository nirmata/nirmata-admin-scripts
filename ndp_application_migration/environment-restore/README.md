# Environment Restore Script 🔥 **ENHANCED**

This script automates the process of copying environment settings from a source cluster to a destination cluster in Nirmata with **advanced safety features, intelligent environment mapping, and comprehensive logging**.

## 🚀 Key Features

### 🔍 **Safety First - Dry Run by Default**
- **Preview mode by default** - See exactly what will be copied before making changes
- **Live mode** - Execute actual changes only when explicitly requested
- **Confirmation prompts** - User approval required for live changes
- **Auto-confirm option** - For automated scripting scenarios

### 🎯 **Intelligent Environment Mapping**
- **6 different pattern matching strategies** to find corresponding destination environments
- **Automatic system namespace detection** - Skips system environments like `kube-system`, `nirmata`
- **Case-insensitive matching** - Handles different naming conventions
- **Fuzzy matching fallback** - Finds environments even with complex naming patterns

### 📊 **Comprehensive Logging**
- **Real-time log location display** at script start and completion
- **Detailed operation logs** with complete API call information
- **Summary logs** with concise results and statistics
- **Mode indicators** clearly showing DRY RUN vs LIVE operations
- **Helpful tips** for reviewing and understanding logs

### 🛡️ **Enterprise-Grade Safety**
- **Transaction-based updates** with proper error handling
- **Backup-before-change** mentality with preview capabilities
- **Granular permission checking** and validation
- **Rollback-friendly logging** with complete audit trails

## 📋 What Gets Copied

The script copies the following settings from source to destination environments:
- **Access Controls (ACLs)** - Team permissions and role bindings
- **Resource Quotas** - CPU, memory, and storage limits
- **Limit Ranges** - Container and namespace resource constraints  
- **Owner Details** - Created by and modified by information
- **Labels** - Environment metadata and annotations
- **Resource Types** - Environment sizing configurations (small, medium, large)

## 🔧 Prerequisites

- `curl` command-line tool
- `jq` JSON processor (version 1.6 or later)
- Bash shell (version 4.0 or later)
- Access to Nirmata API endpoints
- Valid API token with appropriate permissions:
  - Read access to source cluster environments
  - Write access to destination cluster environments
  - Access to manage ACLs, quotas, and limit ranges

## 📖 Usage

### 🔍 **Safe Preview (Recommended - Default)**

```bash
# Preview what will be copied (NO CHANGES MADE)
./restore_env_settings.sh <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER>

# Explicitly specify dry run (same as above)
./restore_env_settings.sh <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER> --dry-run

# Verbose dry run with detailed API responses
./restore_env_settings.sh <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER> --dry-run --verbose
```

### 🚀 **Execute Changes (After Preview)**

```bash
# Make actual changes with confirmation prompts
./restore_env_settings.sh <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER> --live

# Automated execution (skip confirmation prompts)
./restore_env_settings.sh <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER> --live --auto-confirm

# Verbose live mode with detailed API responses
./restore_env_settings.sh <API_ENDPOINT> <API_TOKEN> <SOURCE_CLUSTER> <DEST_CLUSTER> --live --verbose
```

### 📝 **Parameters**

- `API_ENDPOINT`: The Nirmata API endpoint (e.g., `https://staging.nirmata.co`)
- `API_TOKEN`: Your encrypted API token for authentication
- `SOURCE_CLUSTER`: Name of the source cluster (e.g., `conformance-132`)
- `DEST_CLUSTER`: Name of the destination cluster (e.g., `another-rhel9`)

### 🎛️ **Options**

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Preview changes without making them | ✅ **Default** |
| `--live` | Make actual changes | ❌ Explicit |
| `--auto-confirm` | Skip confirmation prompts | ❌ Manual approval |
| `--verbose` | Show detailed API responses | ❌ Standard logging |

## 🎯 Environment Mapping Examples

The script intelligently maps source environments to destination environments:

| Source Environment | Destination Environment | Pattern Used |
|-------------------|----------------------|--------------|
| `conformance-132-shuting` | `shuting-another-rhel9` | Cluster-suffix pattern |
| `satya-conformance-132` | `satya-another-rhel9` | Cluster-suffix pattern |
| `destiny` | `destiny-another-rhel9` | Namespace + cluster pattern |
| `velero-conformance-132` | `velero-another-rhel9` | Cluster-suffix pattern |

### 🔍 **Mapping Strategies**

1. **Exact Match**: Direct name matching
2. **Namespace Extraction**: Intelligent parsing of cluster-namespace patterns
3. **Pattern Matching**: Multiple destination naming conventions
4. **Case-Insensitive**: Handles different case variations
5. **Migration Patterns**: Special cluster-to-cluster migration logic
6. **Fuzzy Matching**: Contains-based fallback for complex names

### 🚫 **System Namespace Detection**

Automatically skips system environments:
- `nirmata*`, `kyverno*`, `ingress-haproxy*`
- `kube-system*`, `kube-public*`, `default*`
- `cert-manager*`, `monitoring*`, `logging*`

## 📊 Logging and Output

### 📁 **Log Files Created**

Each run creates two log files with timestamps:

- **📊 Detailed Log**: `logs/env_restore_YYYYMMDD_HHMMSS.log`
  - Complete operation details
  - API call information (method, URL, data)
  - Error messages and troubleshooting info
  - Processing timeline with timestamps

- **📋 Summary Log**: `logs/env_restore_summary_YYYYMMDD_HHMMSS.log`
  - Concise results overview
  - Environment mapping outcomes  
  - Final statistics and counts
  - Mode indicator (DRY RUN vs LIVE)

### 🖥️ **Console Output**

The script provides real-time feedback:

```
============================================================
🔍 DRY RUN MODE - NO CHANGES WILL BE MADE
   This is a preview of what would happen
   Use --live to actually execute changes
============================================================

📁 LOGGING INFORMATION:
   📊 Detailed Log: logs/env_restore_20250710_130956.log
   📋 Summary Log:  logs/env_restore_summary_20250710_130956.log

========== ENVIRONMENT MAPPING PREVIEW ==========
PREVIEW: MATCH - conformance-132-shuting -> shuting-another-rhel9
PREVIEW: MATCH - satya-conformance-132 -> satya-another-rhel9
PREVIEW: SKIP (system namespace) - kube-system-conformance-132
...

📁 LOG FILES CREATED:
   📊 Detailed Log: logs/env_restore_20250710_130956.log
   📋 Summary Log:  logs/env_restore_summary_20250710_130956.log

🔍 This was a DRY RUN - no actual changes were made to your environments.
   To execute these changes, run the script again with the --live flag:
   ./restore_env_settings.sh https://staging.nirmata.co [TOKEN] conformance-132 another-rhel9 --live

💡 TIP: Review the detailed log file for complete operation details:
   cat logs/env_restore_20250710_130956.log
```

## 🚀 Complete Workflow Example

### Step 1: Safe Preview
```bash
# Preview the environment restore operation
./restore_env_settings.sh https://staging.nirmata.co "YOUR_TOKEN" "conformance-132" "another-rhel9"

# Review the mapping preview and summary
cat logs/env_restore_summary_*.log
```

### Step 2: Execute Changes  
```bash
# Execute the actual changes
./restore_env_settings.sh https://staging.nirmata.co "YOUR_TOKEN" "conformance-132" "another-rhel9" --live

# Review the results
cat logs/env_restore_summary_*.log
```

### Step 3: Verify Success
```bash
# Check the detailed logs for any issues
cat logs/env_restore_*.log | grep -E "(SUCCESS|FAILED|ERROR)"
```

## 🛠️ Error Handling and Troubleshooting

### 🔍 **Common Issues**

#### Authentication Errors
```bash
Error: Not authorized. Please check your token.
```
**Solutions:**
- Verify API token validity and permissions
- Check token format and encoding
- Ensure correct API endpoint

#### Environment Mapping Failures
```bash
ERROR: No corresponding destination environment found for sonobuoy-conformance-132
```
**Solutions:**
- Check if destination environment exists
- Verify naming patterns match supported strategies
- Review environment mapping in dry run mode first

#### Permission Errors
```bash
Failed to create ACL for team vikash-team
```
**Solutions:**
- Verify team exists in destination cluster
- Check API token permissions for ACL management
- Review team role bindings and permissions

### 📊 **Debugging with Logs**

The detailed logs provide extensive debugging information:
```bash
# View detailed API operations
cat logs/env_restore_*.log | grep "🔍 DRY RUN\|🚀 LIVE"

# Check environment mapping decisions
cat logs/env_restore_*.log | grep "Successfully mapped using"

# Review any errors or failures
cat logs/env_restore_*.log | grep -i error
```

## 🔐 Security Considerations

- **API Token Security**: Store tokens securely, use environment variables
- **Permission Principle**: Use tokens with minimal required permissions
- **Audit Trails**: All operations are logged with timestamps
- **Preview First**: Always run dry run mode before live changes
- **Backup Strategy**: Consider backing up destination environments before changes

## ⚡ Performance and Scalability

- **Efficient API Usage**: Batched operations where possible
- **Rate Limiting**: Respects API rate limits with proper error handling
- **Large Environments**: Tested with 100+ environments per cluster
- **Parallel Processing**: Safe concurrent operations where applicable

## 📈 Best Practices

1. **🔍 Always Preview First**: Use dry run mode to understand changes
2. **📊 Review Logs**: Check summary logs before proceeding to live mode
3. **🎯 Verify Mappings**: Ensure environment mappings are correct
4. **🔐 Secure Tokens**: Use environment variables for API tokens
5. **📝 Document Changes**: Keep logs for audit and troubleshooting
6. **🧪 Test in Non-Production**: Validate script behavior in test environments
7. **⏰ Schedule Maintenance**: Run during maintenance windows for live changes

## 🆘 Support and Troubleshooting

For issues or questions:
1. **📊 Check the logs** in the `logs` directory
2. **🔍 Run dry run mode** to diagnose mapping issues  
3. **📝 Review error messages** in detailed logs
4. **🎯 Verify permissions** and API token access
5. **📞 Contact support** with log file references and specific error messages

## 🔄 Version History

- **v2.0** - Enhanced with dry run mode, intelligent mapping, comprehensive logging
- **v1.0** - Basic environment settings copy functionality 