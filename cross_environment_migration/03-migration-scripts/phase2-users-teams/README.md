# 👥 Phase 3: Users & Teams Migration

**Purpose**: Migrate users and teams with complete role and permission preservation

## 👥 Scripts in this Phase

### `copy_cluster_teams_with_full_user_roles.sh` (Recommended)
**What it does**: Complete user and team migration with role preservation
- Extracts actual source user roles (admin, devops, etc.)
- Preserves identity providers (SAML, Azure AD, Local)
- Creates teams with proper user associations
- Maintains user permissions and access levels

**Usage**:
```bash
# Preserve identity providers (recommended for production)
IDENTITY_PROVIDER_MODE=preserve ./copy_cluster_teams_with_full_user_roles.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"

# Convert all to Local (for testing environments)
IDENTITY_PROVIDER_MODE=convert ./copy_cluster_teams_with_full_user_roles.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"
```

### `copy_cluster_teams_with_roles.sh` (Alternative)
**What it does**: Simplified team migration without full user profile creation
- Migrates teams and basic user associations
- Less comprehensive than the full migration script

**Usage**:
```bash
./copy_cluster_teams_with_roles.sh \
  "$SOURCE_API" "$SOURCE_TOKEN" "$SOURCE_CLUSTER" \
  "$DEST_API" "$DEST_TOKEN" "$DEST_CLUSTER"
```

## 📊 What Gets Migrated

- **User Profiles**: Complete user information with roles
- **Identity Providers**: SAML, Azure AD, or Local authentication
- **Team Structures**: Team names, descriptions, and metadata
- **User-Team Associations**: Team memberships and relationships
- **Role Assignments**: Admin, devops, and custom roles

## ✅ Success Criteria

Phase 3 is successful when:
- All users are created or updated in destination
- Teams are created with proper memberships
- User roles are preserved accurately
- Identity providers are handled correctly

## 📋 Expected Output

```
👥 Users: 15/15 successful (12 created, 3 existing)
🏷️  Teams: 4/4 successful
🔐 Roles preserved: admin(8), devops(7)
⚠️  Identity provider conversions: SAML→Local(3)
```

## ⚙️ Configuration Options

### Identity Provider Modes

**Preserve Mode** (Recommended for production):
```bash
export IDENTITY_PROVIDER_MODE="preserve"
```
- Keeps original identity providers when possible
- Converts to Local only when destination doesn't support source provider
- Provides warnings for conversions

**Convert Mode** (For testing):
```bash
export IDENTITY_PROVIDER_MODE="convert"
```
- Converts all users to Local authentication
- Simpler setup but loses SSO integration

## ⚠️ Common Issues

- **User invitation failures**: Destination environment restrictions (common in production)
- **Identity provider mismatches**: SAML/Azure AD not configured in destination
- **Role assignment errors**: Destination requires specific roles during user creation
- **Duplicate users**: Users already exist with different configurations

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

After Phase 3 succeeds, proceed to:
**Phase 4**: `../phase4-applications/` 