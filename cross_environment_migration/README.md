# Cross-Environment NDP Application Migration Scripts

This directory contains scripts specifically designed for migrating applications between **different Nirmata environments** (different API endpoints with different authentication tokens).

## Use Case
Use these scripts when your source and destination clusters are in **different Nirmata environments**:
- Source: `https://pe420.nirmata.co` (Production environment)
- Destination: `https://staging.nirmata.co` (Staging environment)

## Prerequisites
- `curl` installed
- `jq` installed  
- Bash shell
- Valid API tokens for both source and destination environments
- Network access to both API endpoints
- Corresponding Git credentials in both environments
- Teams and roles exist in both environments

## Scripts Overview

### 1. **restore_env_settings_cross_env.sh**
Migrates environment settings, team permissions, and access controls between different Nirmata environments.

**What it does:**
- Copies team rolebindings from source to destination environments
- Maps teams and roles between environments
- Validates authentication for both environments
- Handles environment matching intelligently

### 2. **migrate_env_apps_to_catalog_cross_env.sh**
Migrates Git-based applications from source environments to destination catalogs.

**What it does:**
- Creates catalogs in destination environment if they don't exist
- Migrates Git-based applications to catalog applications
- Maps Git credentials between environments
- Preserves application metadata and Git configurations
- Skips non-Git applications (as they can't be catalogized)

### 3. **update_catalog_references_cross_env.sh**
Updates application references in destination environments to point to migrated catalog applications.

**What it does:**
- Finds catalog applications in destination environment
- Updates application references in destination environments
- Uses intelligent pattern matching to find corresponding applications
- Handles retry logic for failed updates

## Migration Process

### Step 1: Environment Settings Migration
```bash
./scripts/restore_env_settings_cross_env.sh \
    <source_api_endpoint> <source_token> <source_cluster> \
    <dest_api_endpoint> <dest_token> <dest_cluster>
```

### Step 2: Application Migration to Catalog
```bash
./scripts/migrate_env_apps_to_catalog_cross_env.sh \
    <source_api_endpoint> <source_token> <source_cluster> \
    <dest_api_endpoint> <dest_token> <dest_cluster>
```

### Step 3: Update Catalog References
```bash
./scripts/update_catalog_references_cross_env.sh \
    <source_api_endpoint> <source_token> <source_cluster> \
    <dest_api_endpoint> <dest_token> <dest_cluster>
```

## Example Usage

### Real-world Example
```bash
# Source Environment: pe420.nirmata.co, Cluster: 123-app-migration
# Destination Environment: staging.nirmata.co, Cluster: conformance-132

# Step 1: Migrate environment settings
./scripts/restore_env_settings_cross_env.sh \
    "https://pe420.nirmata.co" \
    "W6mdT3taq2nkLxmmJFyHfpMzrUeow0HTeQQx3/n7lvXfJYyT7l+Rd3oaSwR7NJyyRhnOQWF7nH1aNHYsEJURZg==" \
    "123-app-migration" \
    "https://staging.nirmata.co" \
    "c7/tRvOi3shNloGDjtWABf/KKckLjeNNf7q1N81uTrAMA7YXxuJ43prRuQYjR4RRFssLshsT39SxvlWIeRKNIg==" \
    "conformance-132"

# Step 2: Migrate applications to catalog
./scripts/migrate_env_apps_to_catalog_cross_env.sh \
    "https://pe420.nirmata.co" \
    "W6mdT3taq2nkLxmmJFyHfpMzrUeow0HTeQQx3/n7lvXfJYyT7l+Rd3oaSwR7NJyyRhnOQWF7nH1aNHYsEJURZg==" \
    "123-app-migration" \
    "https://staging.nirmata.co" \
    "c7/tRvOi3shNloGDjtWABf/KKckLjeNNf7q1N81uTrAMA7YXxuJ43prRuQYjR4RRFssLshsT39SxvlWIeRKNIg==" \
    "conformance-132"

# Step 3: Update catalog references
./scripts/update_catalog_references_cross_env.sh \
    "https://pe420.nirmata.co" \
    "W6mdT3taq2nkLxmmJFyHfpMzrUeow0HTeQQx3/n7lvXfJYyT7l+Rd3oaSwR7NJyyRhnOQWF7nH1aNHYsEJURZg==" \
    "123-app-migration" \
    "https://staging.nirmata.co" \
    "c7/tRvOi3shNloGDjtWABf/KKckLjeNNf7q1N81uTrAMA7YXxuJ43prRuQYjR4RRFssLshsT39SxvlWIeRKNIg==" \
    "conformance-132"
```

### Using the Example Script
For convenience, you can use the example script:
```bash
# Edit the tokens and endpoints in the example script first
./examples/run_cross_env_migration_example.sh
```

## Directory Structure
```
cross_environment_migration/
├── scripts/
│   ├── restore_env_settings_cross_env.sh
│   ├── migrate_env_apps_to_catalog_cross_env.sh
│   └── update_catalog_references_cross_env.sh
├── examples/
│   └── run_cross_env_migration_example.sh
├── logs/
│   └── (Generated log files)
└── README.md
```

## Log Files
All scripts generate detailed logs in the `logs/` directory:
- `env_restore_cross_env_<timestamp>.log`
- `env_restore_summary_cross_env_<timestamp>.log`
- `migration_<source_cluster>_to_<dest_cluster>_<timestamp>.log`
- `catalog_reference_update_cross_env_<timestamp>.log`

## Application Naming Convention
Migrated applications follow this naming pattern:
- **Original**: `nginx-app`
- **Catalog Application**: `app-nginx-app-<source_cluster_name>`
- **Example**: `app-nginx-pvc-gitops-123-app-migration`

## Git Credential Handling
- Scripts attempt to find matching Git credentials in destination by name
- If no match found, uses the first available Git credential
- Git credential names are preserved, but sensitive data stays secure
- Verify Git credentials exist in destination before migration

## Cross-Environment Considerations

### Authentication
- Each environment requires its own API token
- Tokens must have appropriate permissions for:
  - Reading source applications and environments
  - Creating catalogs and applications in destination
  - Managing team rolebindings and permissions

### Network Access
- Ensure connectivity to both API endpoints
- Check firewall rules and network policies
- Verify SSL/TLS certificates if using custom domains

### Team and Role Mapping
- Teams must exist in both environments with the same names
- Roles are mapped using standard Nirmata role names
- Review team memberships after migration

### Git Repository Access
- Git repositories must be accessible from destination environment
- SSH keys or tokens must be configured in destination
- Private repositories require proper credential setup

## Verification Steps

### 1. Check Logs
Review all log files for errors or warnings:
```bash
ls -la logs/
tail -50 logs/migration_*.log
```

### 2. Verify in Destination UI
- **Catalogs**: Check that catalogs were created with expected names
- **Applications**: Verify catalog applications exist with proper Git configs
- **Environments**: Confirm team rolebindings and permissions
- **Git Credentials**: Ensure credentials are available and referenced correctly

### 3. Test Application Deployment
Deploy a migrated catalog application to verify end-to-end functionality.

## Known Limitations

### Current Issues
1. **Catalog Reference Updates**: May fail if destination environments don't have applications to update
2. **Pattern Matching**: Might not find catalog applications if naming doesn't match expected patterns
3. **Environment Matching**: Requires environments to exist in destination cluster

### Workarounds
1. **Manual Verification**: Always verify results in Nirmata UI
2. **Manual Reference Updates**: May need to manually link applications to catalogs
3. **Incremental Migration**: Consider migrating one environment at a time

## Troubleshooting

### Authentication Errors
```bash
# Test source environment access
curl -H "Authorization: NIRMATA-API <source_token>" <source_endpoint>/environments/api/clusters

# Test destination environment access  
curl -H "Authorization: NIRMATA-API <dest_token>" <dest_endpoint>/environments/api/clusters
```

### Git Credential Issues
- Verify credential names match between environments
- Check Git repository accessibility from destination
- Ensure proper permissions on Git credentials

### Application Migration Failures
- Check for missing Git credentials in source applications
- Verify Git repository URLs are accessible
- Review application dependencies and configurations

### Catalog Reference Update Issues
- Verify destination environments exist and have applications
- Check catalog application names match expected patterns
- Review pattern matching logic in logs

## Support
For issues or questions:
1. Check the logs in the `logs/` directory
2. Review error messages and API responses
3. Verify authentication and network connectivity
4. Contact support with log files and specific error messages

## Best Practices
1. **Test First**: Always test in non-production environments
2. **Backup**: Ensure proper backups exist before migration
3. **Incremental**: Migrate one cluster/environment at a time
4. **Verify**: Check each step before proceeding to the next
5. **Document**: Keep track of what was migrated and any manual steps
6. **Security**: Keep API tokens secure and rotate them regularly 