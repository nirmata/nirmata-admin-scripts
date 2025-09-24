# Identity Provider Migration Guide

## Overview
This guide explains how to properly handle identity providers (SAML, Azure AD, Local) during cross-environment user migration.

## ⚠️ Critical Issue
**DO NOT** migrate SAML/Azure AD users to environments that only support Local authentication. This will:
- Break SSO authentication for users
- Force users to reset passwords
- Lose centralized identity management
- Create security and compliance issues

## Pre-Migration Checklist

### 1. Check Source Identity Providers
```bash
# Check what identity providers are used in source
curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
  "$SOURCE_API_ENDPOINT/users/api/users" | \
  jq '[.[] | .identityProvider] | unique'
```

### 2. Check Destination Identity Providers
```bash
# Check what identity providers are supported in destination
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API_ENDPOINT/users/api/users" | \
  jq '[.[] | .identityProvider] | unique'
```

### 3. Configure SAML/Azure AD in Destination (If Needed)

#### For Customer Environments:
1. **Contact Nirmata Support** to enable SAML/Azure AD
2. **Configure SAML/Azure AD** in destination environment
3. **Test SSO login** before migration
4. **Verify identity provider** appears in destination users

#### Configuration Steps:
- Access destination Nirmata environment
- Go to Settings → Identity & Access → SAML/Azure AD
- Configure SSO with your identity provider
- Test with a test user
- Verify the identity provider shows up in API

## Migration Modes

### Mode 1: Preserve Identity Providers (Recommended)
```bash
# Default mode - preserves source identity providers
IDENTITY_PROVIDER_MODE=preserve ./copy_cluster_teams_with_full_user_roles.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://dest.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

**Behavior:**
- ✅ Preserves SAML/Azure AD users as SAML/Azure AD
- ⚠️ Converts to Local only if destination doesn't support source identity provider
- 🚨 Shows warnings for identity provider mismatches

### Mode 2: Force Convert to Local (Use with Caution)
```bash
# Force all users to Local identity provider
IDENTITY_PROVIDER_MODE=convert ./copy_cluster_teams_with_full_user_roles.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://dest.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

**Behavior:**
- 🔄 Converts ALL users to Local identity provider
- ⚠️ SAML/Azure AD users will lose SSO access
- 📧 Users will need to reset passwords

## Best Practices for Customer Environments

### 1. Pre-Migration
- [ ] Audit source identity providers
- [ ] Configure matching identity providers in destination
- [ ] Test SSO functionality in destination
- [ ] Communicate with users about potential impacts

### 2. During Migration
- [ ] Use `IDENTITY_PROVIDER_MODE=preserve`
- [ ] Monitor logs for identity provider warnings
- [ ] Verify user creation success rates

### 3. Post-Migration
- [ ] Test SSO login for migrated users
- [ ] Verify team memberships and permissions
- [ ] Update any service accounts or API tokens

## Common Identity Provider Configurations

### Azure AD
```json
{
  "identityProvider": "Azure AD",
  "samlConfiguration": {
    "ssoUrl": "https://login.microsoftonline.com/.../saml2",
    "entityId": "urn:microsoft:azure:...",
    "certificate": "..."
  }
}
```

### SAML
```json
{
  "identityProvider": "SAML", 
  "samlConfiguration": {
    "ssoUrl": "https://your-idp.com/sso",
    "entityId": "your-entity-id",
    "certificate": "..."
  }
}
```

### Local
```json
{
  "identityProvider": "Local",
  "passwordPolicy": {
    "minLength": 8,
    "requireUppercase": true,
    "requireNumbers": true
  }
}
```

## Troubleshooting

### Issue: SAML users converted to Local
**Cause:** Destination doesn't support SAML
**Solution:** Configure SAML in destination before migration

### Issue: Azure AD users can't login
**Cause:** Azure AD not configured in destination
**Solution:** Set up Azure AD integration in destination

### Issue: Users lose team memberships
**Cause:** Identity provider mismatch affects user resolution
**Solution:** Ensure identity providers match between environments

## Support
For SAML/Azure AD configuration in customer environments:
- Contact Nirmata Support
- Provide your Azure AD/SAML configuration details
- Request SSO enablement for destination environment 