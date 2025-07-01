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