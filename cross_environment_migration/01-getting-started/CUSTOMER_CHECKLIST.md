# 📋 Customer Pre-Migration Checklist

## 🎯 **Before You Start - Complete This Checklist**

### ✅ **Step 1: Get Your API Tokens**

#### **Finding Your API Token in Nirmata UI:**
1. **Login to Nirmata** → Click your profile (top right) → **Settings**
2. **Navigate to**: `Settings` → `Access Control` → `API Keys`
3. **Create New API Key**:
   - Name: `Migration-Source-Token` (or similar)
   - **Required Permissions**: 
     - ✅ Read Users and Teams
     - ✅ Read Environments and Clusters  
     - ✅ Read Applications and Catalogs
     - ✅ Create/Update Teams (for destination)
     - ✅ Create/Update Users (for destination)
4. **Copy the token** - you'll need it in configuration

#### **Test Your Tokens:**
```bash
# Test Source Token
curl -s -H "Authorization: NIRMATA-API YOUR_SOURCE_TOKEN" \
  "https://your-source.nirmata.co/users/api/users" | jq 'length'

# Test Destination Token  
curl -s -H "Authorization: NIRMATA-API YOUR_DEST_TOKEN" \
  "https://your-dest.nirmata.co/users/api/users" | jq 'length'

# Should return numbers, not errors
```

### ✅ **Step 2: Find Your Cluster Names**

#### **List Available Clusters:**
```bash
# Source clusters
curl -s -H "Authorization: NIRMATA-API YOUR_SOURCE_TOKEN" \
  "https://your-source.nirmata.co/environments/api/clusters" | \
  jq '.[] | {name: .name, state: .state, id: .id}'

# Destination clusters
curl -s -H "Authorization: NIRMATA-API YOUR_DEST_TOKEN" \
  "https://your-dest.nirmata.co/environments/api/clusters" | \
  jq '.[] | {name: .name, state: .state, id: .id}'
```

#### **Choose Your Clusters:**
- **Source Cluster**: The cluster you want to migrate FROM
- **Destination Cluster**: The cluster you want to migrate TO
- **Write them down** - you'll need exact names for configuration

### ✅ **Step 3: Check What You're Migrating**

#### **Preview Source Data:**
```bash
# How many users?
curl -s -H "Authorization: NIRMATA-API YOUR_SOURCE_TOKEN" \
  "https://your-source.nirmata.co/users/api/users" | jq 'length'

# How many teams?
curl -s -H "Authorization: NIRMATA-API YOUR_SOURCE_TOKEN" \
  "https://your-source.nirmata.co/users/api/teams" | jq 'length'

# How many environments in your cluster?
curl -s -H "Authorization: NIRMATA-API YOUR_SOURCE_TOKEN" \
  "https://your-source.nirmata.co/environments/api/environments" | \
  jq '[.[] | select(.cluster == "YOUR_SOURCE_CLUSTER")] | length'
```

### ✅ **Step 4: Identity Provider Check (CRITICAL)**

#### **Check Source Identity Providers:**
```bash
curl -s -H "Authorization: NIRMATA-API YOUR_SOURCE_TOKEN" \
  "https://your-source.nirmata.co/users/api/users" | \
  jq '[.[] | .identityProvider] | unique'
```

#### **If You See SAML or Azure AD:**
🚨 **STOP!** You MUST configure SAML/Azure AD in destination BEFORE migration:
1. **Contact Nirmata Support** to enable SSO in destination
2. **Configure SAML/Azure AD** in destination environment
3. **Test SSO login** in destination before proceeding

### ✅ **Step 5: Backup and Safety**

#### **Create Backup (Recommended):**
```bash
# Export current destination state (just in case)
mkdir -p backup/$(date +%Y%m%d)
curl -s -H "Authorization: NIRMATA-API YOUR_DEST_TOKEN" \
  "https://your-dest.nirmata.co/users/api/users" > backup/$(date +%Y%m%d)/users.json
curl -s -H "Authorization: NIRMATA-API YOUR_DEST_TOKEN" \
  "https://your-dest.nirmata.co/users/api/teams" > backup/$(date +%Y%m%d)/teams.json
```

#### **Timing Considerations:**
- **Maintenance Window**: Plan for 1-3 hours depending on data size
- **User Communication**: Inform users about potential brief disruptions
- **Rollback Plan**: Know how to restore from backup if needed

### ✅ **Step 6: Environment Readiness**

#### **Check Prerequisites:**
```bash
# Required tools
which curl jq bash git || echo "❌ Install missing tools"

# Network connectivity
ping your-source.nirmata.co
ping your-dest.nirmata.co

# Disk space (for logs)
df -h . | grep -v Filesystem
```

#### **Git Access (If You Have Git-Based Apps):**
- **Git credentials** must be configured in destination
- **Repository access** from destination environment
- **Test git clone** from destination if possible

## 🎯 **Ready to Start? Configuration Example**

Once you've completed the checklist, your `02-configuration/migration_config.sh` should look like:

```bash
# Real example based on your findings:
export SOURCE_API="https://company-prod.nirmata.co"
export SOURCE_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."  # Your actual token
export SOURCE_CLUSTER="production-k8s-cluster"  # From cluster list

export DEST_API="https://company-staging.nirmata.co" 
export DEST_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."  # Your actual token
export DEST_CLUSTER="staging-k8s-cluster"  # From cluster list

export IDENTITY_PROVIDER_MODE="preserve"  # or "convert" if no SSO in dest
```

## 🚨 **Red Flags - STOP if You See These:**

- ❌ **401 Unauthorized** when testing tokens
- ❌ **Empty cluster list** (no clusters found)
- ❌ **SAML users but no SSO in destination**
- ❌ **Network timeouts** to either environment
- ❌ **No users/teams in source** (nothing to migrate)

## ✅ **Green Lights - Proceed if You See These:**

- ✅ **Both API tokens work** (return data, not errors)
- ✅ **Clusters exist** in both environments
- ✅ **Source has data** (users, teams, environments)
- ✅ **Identity providers match** or conversion plan ready
- ✅ **Network connectivity** to both environments

---

## 🚀 **Next Step After Checklist:**

```bash
# If all checks pass, start the migration:
cd 03-migration-scripts/phase1-validation
./RUN_THIS_PHASE.sh
```

**Remember**: The migration runs **phase by phase**. You can stop, check results, and fix issues between each phase! 