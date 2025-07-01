# 📱 Phase 4: Application Migration

**Purpose**: Convert Git-based applications to catalog applications and update references

## 📱 Scripts in this Phase

### `migrate_env_apps_to_catalog_cross_env.sh` (Step 4a)
**What it does**: Convert Git-based applications to catalog applications
- Finds Git-based applications in source environments
- Creates catalog applications in destination environment
- Preserves application configurations and Git settings
- Maps Git credentials between environments

**Usage**:
```bash
./migrate_env_apps_to_catalog_cross_env.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"
```

### `update_catalog_references_cross_env.sh` (Step 4b)
**What it does**: Update application references in destination environments
- Points applications to new catalog applications
- Updates environment references
- Maintains deployment configurations
- Preserves application relationships

**Usage**:
```bash
./update_catalog_references_cross_env.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"
```

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
- Application references are updated in destination environments
- Git credentials are properly mapped
- No broken application dependencies

## 📋 Expected Output

```
📦 Applications processed: 25/25
✅ Catalog applications created: 18/18
🔗 References updated: 42/42
⚠️  Skipped non-Git apps: 7
```

## 🏷️ Application Naming Convention

Migrated applications follow this pattern:
- **Original**: `nginx-app`
- **Catalog Application**: `app-nginx-app-<source_cluster_name>`
- **Example**: `app-nginx-pvc-gitops-123-app-migration`

## ⚠️ Common Issues

- **Git credential mapping failures**: No matching credentials in destination
- **Repository access issues**: Private repositories not accessible from destination
- **Catalog creation failures**: Insufficient permissions or naming conflicts
- **Reference update failures**: Applications not found or already updated

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