# 🏗️ Phase 2: Environment Migration

**Purpose**: Migrate environment settings, policies, and team permissions

## 🏗️ Scripts in this Phase

### `restore_env_settings_cross_env.sh`
**What it does**: Complete environment migration
- Copies environment configurations from source to destination
- Migrates team role bindings and permissions
- Preserves environment policies and settings
- Transfers environment metadata

**Usage**:
```bash
./restore_env_settings_cross_env.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"
```

## 📊 What Gets Migrated

- **Environment Configurations**: Settings, policies, resource limits
- **Team Role Bindings**: Team permissions for each environment
- **Access Controls**: Environment-specific access rules
- **Metadata**: Environment descriptions, labels, annotations

## ✅ Success Criteria

Phase 2 is successful when:
- All environments are copied to destination cluster
- Team role bindings are preserved
- Environment policies are intact
- No configuration drift between source and destination

## 📋 Expected Output

```
✅ Environments migrated: 7/7
✅ Team rolebindings copied: 15/15
✅ Policies preserved: 12/12
⚠️  Warnings: 2 (see log for details)
```

## ⚠️ Common Issues

- **Team role binding failures**: Destination may not support team permissions (system clusters)
- **Policy conflicts**: Some policies may not be compatible with destination
- **Permission issues**: Insufficient privileges to create environments
- **Naming conflicts**: Environment names already exist in destination

## 📋 Next Steps

After Phase 2 succeeds, proceed to:
**Phase 3**: `../phase3-users-teams/` 