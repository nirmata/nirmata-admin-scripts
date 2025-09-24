# 👥 Phase 2: Users & Teams Migration

**Purpose**: Migrate users and teams with complete role and permission preservation

## 🧪 Scripts in this Phase

### `copy_cluster_teams_with_full_user_roles.sh`
**What it does**: Complete user and team migration with role preservation
- Migrates user profiles with roles (admin, devops, etc.)
- Preserves identity providers (SAML, Azure AD, Local)
- Creates team structures and memberships
- Handles user-team associations properly

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
./copy_cluster_teams_with_full_user_roles.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"

# Or run via RUN_THIS_PHASE.sh
./RUN_THIS_PHASE.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

### `copy_cluster_teams_with_roles.sh`
**What it does**: Alternative team migration script
- Simpler team migration without full user profiles
- Useful for basic team structure copying

**Arguments**: Same 6 arguments as above

**Usage**:
```bash
./copy_cluster_teams_with_roles.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

## 📊 What Gets Migrated

- **User Profiles**: Complete user information with roles
- **Identity Providers**: SAML, Azure AD, or Local authentication
- **Team Structures**: Team names, descriptions, and metadata
- **User-Team Associations**: Team memberships and relationships
- **Role Assignments**: Admin, devops, and custom roles

## 🔧 Identity Provider Modes

### `preserve` (Default)
- Tries to preserve original identity providers (SAML, Azure AD)
- Warns if destination doesn't support source identity provider
- Falls back to Local if needed

### `convert`
- Forces all users to Local identity provider
- Use when destination doesn't support SSO
- Users will need to reset passwords

## ✅ Success Criteria

Phase 2 is successful when:
- All users are created in destination with correct roles
- Teams are created with proper memberships
- Identity providers are handled correctly
- No authentication errors occur

## 📊 **Comprehensive Logging**

Phase 2 automatically creates detailed logs for audit and troubleshooting:

### **📁 Log Files Created**
- **Detailed Log**: `../../06-logs/phase2_users_teams_TIMESTAMP.log`
  - Complete console output with timestamps
  - All API requests and responses
  - User and team creation details
  - Role merging decisions and conflicts

- **Summary Log**: `../../06-logs/phase2_users_teams_summary_TIMESTAMP.log`
  - Migration statistics (users/teams migrated)
  - Success/failure status
  - Key metrics for reporting
  - Next steps and troubleshooting guidance

### **📋 Example Log Output**
```bash
📄 Log file: ../../06-logs/phase2_users_teams_20250701_143022.log
📄 Summary: ../../06-logs/phase2_users_teams_summary_20250701_143022.log

Migration Results:
✅ Users migrated: 13
✅ Teams migrated: 3
✅ Roles preserved with merge logic
✅ Identity providers handled correctly
```

### **🔍 What Gets Logged**
- User creation/update operations
- Role merging decisions (existing + new roles)
- Team membership changes
- Identity provider handling
- API errors and troubleshooting information

## 📋 Expected Output

```
👥 Users: 15/15 successful (12 created, 3 existing)
🏷️  Teams: 4/4 successful
🔐 Roles preserved: admin(8), devops(7)
⚠️  Identity provider conversions: SAML→Local(3)
```

## ⚠️ Common Issues

- **User invitation failures**: Production environments may restrict user creation
- **Identity provider mismatches**: Configure SAML/Azure AD in destination first
- **Role assignment errors**: Check required roles exist in destination
- **Permission issues**: Ensure destination token has user management privileges

## 🔧 Troubleshooting

### User Creation Failures
```bash
# Check available roles in destination
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/users/api/users" | jq 'group_by(.role) | map({role: .[0].role, count: length})'
```

### Identity Provider Issues
```bash
# Check supported identity providers
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/users/api/users" | jq '[.[] | .identityProvider] | unique'
```

## 📋 Next Steps

After Phase 2 succeeds, proceed to:
**Phase 3**: `../phase3-environments/` 