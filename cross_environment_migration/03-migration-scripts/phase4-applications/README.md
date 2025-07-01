# 📱 Phase 4: Application Migration

**Purpose**: Migrate applications from environments to catalog-based deployments

## 🧪 Scripts in this Phase

### `migrate_env_apps_to_catalog_cross_env.sh`
**What it does**: Converts environment-based Git applications to catalog applications
- Identifies Git-based applications in source environments
- Creates corresponding catalog applications in destination
- Handles Git credential mapping and repository references
- Preserves application configurations and metadata

**Arguments**: Requires 6 arguments in this order:
1. `source_api_endpoint` - Source Nirmata API URL
2. `source_token` - Source API token
3. `source_cluster` - Source cluster name
4. `dest_api_endpoint` - Destination Nirmata API URL
5. `dest_token` - Destination API token
6. `dest_cluster` - Destination cluster name

**Usage**:
```bash
# Direct script call
./migrate_env_apps_to_catalog_cross_env.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"

# Or run via RUN_THIS_PHASE.sh
./RUN_THIS_PHASE.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

### `update_catalog_references_cross_env.sh`
**What it does**: Updates application references in environments to use catalog apps
- Scans destination environments for application references
- Updates references to point to newly created catalog applications
- Ensures applications are properly linked to environments
- Maintains application deployment configurations

**Arguments**: Requires 6 arguments in this order:
1. `source_api_endpoint` - Source Nirmata API URL
2. `source_token` - Source API token
3. `source_cluster` - Source cluster name
4. `dest_api_endpoint` - Destination Nirmata API URL
5. `dest_token` - Destination API token
6. `dest_cluster` - Destination cluster name

**Usage**:
```bash
# Direct script call
./update_catalog_references_cross_env.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"

# Or run via RUN_THIS_PHASE.sh
./RUN_THIS_PHASE.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

## 📋 Prerequisites

- **Phase 3 completed**: Environments must exist in destination
- **Git credentials**: Ensure Git credentials are configured in destination
- **Catalog access**: Destination token must have catalog management permissions

## 🔄 Migration Process

1. **Phase 4a**: Convert Git apps to catalog apps (`migrate_env_apps_to_catalog_cross_env.sh`)
2. **Phase 4b**: Update environment references (`update_catalog_references_cross_env.sh`)

## 📊 What Gets Migrated

### Step 4a: Git → Catalog Conversion
- **Git-based Applications**: Converted to catalog applications
- **Application Configurations**: Deployment settings, resource limits
- **Git Repository Information**: Repository URLs, branches, paths
- **Git Credentials**: Mapped to destination environment credentials

### Step 4b: Reference Updates
- **Environment References**: Updated to point to new catalog apps
- **Application Dependencies**: Maintained between applications
- **Deployment Configurations**: Preserved with new references

## ✅ Success Criteria

Phase 4 is successful when:
- All Git-based applications are converted to catalog applications
- Application references in environments are updated correctly
- Git credentials are properly mapped
- No broken application links remain

## 📋 Expected Output

```
Phase 4a: Application Migration
Git-based applications found: 5
Successfully created catalog apps: 5
Failed applications: 0

Phase 4b: Reference Updates
Applications processed: 88
References updated: 12
Warnings: 0
```

## 🏷️ Application Naming Convention

Migrated applications follow this pattern:
- **Original**: `nginx-app`
- **Catalog Application**: `app-nginx-app-<source_cluster_name>`
- **Example**: `app-nginx-pvc-gitops-123-app-migration`

## ⚠️ Common Issues

- **Git credential mapping failures**: Ensure Git credentials exist in destination
- **Application creation errors**: Check catalog permissions and naming conflicts
- **Reference update failures**: Verify environment and application IDs are correct
- **No Git apps found**: Source may only have catalog apps (this is normal)

## 🔧 Troubleshooting

### Git Credential Issues
```bash
# Check available Git credentials in destination
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/catalog/api/gitCredentials"
```

### Repository Access
```bash
# Test repository access
git ls-remote https://github.com/your-repo/app.git
```

### Catalog Application Status
```bash
# Check created catalog applications
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/catalog/api/catalogapplications" | jq '.[] | {name: .name, status: .status}'
```

## 📋 Execution Order

**Important**: Run these scripts in order:
1. **First**: `migrate_env_apps_to_catalog_cross_env.sh` (Step 4a)
2. **Then**: `update_catalog_references_cross_env.sh` (Step 4b)

Step 4b depends on catalog applications created in Step 4a.

## 🎯 What Applications Are Migrated

### ✅ **Migrated**:
- Git-based applications (Helm charts, Kubernetes manifests)
- Applications with Git repository configurations
- Applications deployed from Git sources

### ❌ **Not Migrated**:
- Catalog applications (already catalog-based)
- System applications
- Applications without Git configurations

## 📋 Next Steps

After Phase 4 succeeds, proceed to:
**Phase 5**: `../phase5-verification/` 