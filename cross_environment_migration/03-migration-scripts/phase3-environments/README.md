# 🏗️ Phase 3: Environment Migration

**Purpose**: Migrate environment settings, policies, and team permissions

## 🧪 Scripts in this Phase

### `restore_env_settings_cross_env.sh`
**What it does**: Complete environment migration with team permissions
- Migrates environment configurations and settings
- Copies team role bindings and permissions
- Preserves environment policies and metadata
- Associates teams with environments (requires teams to exist from Phase 2)

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
./restore_env_settings_cross_env.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"

# Or run via RUN_THIS_PHASE.sh
./RUN_THIS_PHASE.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

## 📋 Prerequisites

**Critical**: Phase 2 (Users & Teams) must be completed first!
- Teams must exist in destination before environment migration
- Team permissions cannot be assigned to non-existent teams
- This is why Phase 2 comes before Phase 3 in the migration flow

## 🔄 What Gets Migrated

- **Environment Settings**: Configuration, policies, metadata
- **Team Permissions**: Role bindings between teams and environments  
- **Environment Policies**: Security and access policies
- **Cluster Associations**: Environment-to-cluster mappings

## ✅ Success Criteria

Phase 3 is successful when:
- All environments are created in destination cluster
- Team permissions are properly assigned (no "team not found" warnings)
- Environment configurations match source settings
- Policies and metadata are preserved

## ⚠️ Common Issues

- **Team not found warnings**: Indicates Phase 2 wasn't completed or failed
- **Permission assignment failures**: Check team permissions in destination
- **Environment creation errors**: Verify cluster exists and token has permissions
- **Policy conflicts**: Some policies may not be compatible between environments

## 📋 Expected Output

```
Successfully migrated environments: 7
Team permissions assigned: 15
Warnings: 0 (no missing teams)
```

## 📋 Next Steps

After Phase 3 succeeds, proceed to:
**Phase 4**: `../phase4-applications/` 