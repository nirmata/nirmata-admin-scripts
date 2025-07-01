# 🔧 Customer Troubleshooting Guide

## 🚨 **Most Common Customer Issues**

### ❌ **"401 Unauthorized" Error**
```bash
# Error message:
curl: (22) The requested URL returned error: 401 Unauthorized
```

**🔍 What this means**: Your API token is wrong or expired

**✅ Solutions**:
1. **Check token in Nirmata UI**: Settings → Access Control → API Keys
2. **Regenerate token** if it's old
3. **Test token manually**:
```bash
curl -s -H "Authorization: NIRMATA-API YOUR_TOKEN" \
  "https://your-env.nirmata.co/users/api/users" | jq 'length'
```

### ❌ **"Cluster not found" Error**
```bash
# Error message:
ERROR: Source cluster 'my-cluster' not found
```

**🔍 What this means**: Cluster name is wrong or doesn't exist

**✅ Solutions**:
1. **List available clusters**:
```bash
curl -s -H "Authorization: NIRMATA-API YOUR_TOKEN" \
  "https://your-env.nirmata.co/environments/api/clusters" | \
  jq '.[] | .name'
```
2. **Copy exact cluster name** (case-sensitive!)
3. **Update configuration** with correct name

### ❌ **"jq: command not found"**
```bash
# Error message:
./RUN_THIS_PHASE.sh: line 15: jq: command not found
```

**🔍 What this means**: Missing required tools

**✅ Solutions**:
```bash
# Ubuntu/Debian:
sudo apt-get install jq curl

# CentOS/RHEL:
sudo yum install jq curl

# macOS:
brew install jq

# Test installation:
jq --version
```

### ❌ **"SAML users will lose access" Warning**
```bash
# Warning message:
🚨 CRITICAL WARNING: Source has 6 SAML users
🚨 But destination only supports: Local
```

**🔍 What this means**: Users won't be able to login after migration

**✅ Solutions**:
1. **Contact Nirmata Support** to enable SAML in destination
2. **Configure SAML/Azure AD** in destination environment
3. **Test SSO login** in destination before proceeding
4. **Or set**: `IDENTITY_PROVIDER_MODE="convert"` (users will need new passwords)

### ❌ **"Connection timeout" Error**
```bash
# Error message:
curl: (28) Failed to connect to staging.nirmata.co port 443: Connection timed out
```

**🔍 What this means**: Network connectivity issues

**✅ Solutions**:
1. **Check internet connection**
2. **Test DNS resolution**: `nslookup your-env.nirmata.co`
3. **Check firewall**: Allow HTTPS (port 443) outbound
4. **Verify URL**: Make sure environment URL is correct

### ❌ **"No users found" or "No teams found"**
```bash
# Error message:
Source environment has no users/teams to migrate
```

**🔍 What this means**: Source environment is empty or wrong cluster

**✅ Solutions**:
1. **Verify source cluster**: Is this the right cluster to migrate?
2. **Check cluster permissions**: Does your token have access to this cluster?
3. **List users manually**:
```bash
curl -s -H "Authorization: NIRMATA-API YOUR_TOKEN" \
  "https://your-env.nirmata.co/users/api/users" | jq 'length'
```

## 🛠️ **Quick Diagnostic Commands**

### **Test Everything is Working:**
```bash
# 1. Test tools
which curl jq bash || echo "❌ Missing tools"

# 2. Test source connectivity
curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
  "$SOURCE_API/users/api/users" | jq 'type'

# 3. Test destination connectivity  
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/users/api/users" | jq 'type'

# 4. Test cluster exists
curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" \
  "$SOURCE_API/environments/api/clusters" | \
  jq ".[] | select(.name == \"$SOURCE_CLUSTER\") | .name"

# All should return data, not errors
```

### **Check What You're Migrating:**
```bash
# Load your config first
source 02-configuration/migration_config.sh

# Count source data
echo "Users: $(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API/users/api/users" | jq 'length')"
echo "Teams: $(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API/users/api/teams" | jq 'length')"
echo "Environments: $(curl -s -H "Authorization: NIRMATA-API $SOURCE_TOKEN" "$SOURCE_API/environments/api/environments" | jq 'length')"
```

## 📋 **Phase-Specific Issues**

### **Phase 1 (Validation) Issues:**
- **Test failures**: Review checklist - usually API tokens or cluster names
- **Identity provider warnings**: Plan SSO configuration before proceeding

### **Phase 2 (Users/Teams) Issues:**
- **User creation failures**: Check destination permissions
- **Team association errors**: Usually resolved by re-running the phase

### **Phase 3 (Environments) Issues:**
- **Environment creation failures**: Check cluster permissions
- **Team assignment warnings**: Normal if teams don't have environment permissions

### **Phase 4 (Applications) Issues:**
- **Git credential errors**: Configure Git access in destination
- **Catalog creation failures**: Check application permissions

### **Phase 5 (Verification) Issues:**
- **Validation failures**: Review previous phase logs
- **User/team not found**: Re-run previous phases if needed

## 🆘 **When to Get Help**

**Contact Nirmata Support if:**
- ❌ **SSO configuration** needed in destination
- ❌ **API permission** issues persist
- ❌ **Environment corruption** after migration
- ❌ **Data integrity** problems

**Check Documentation if:**
- 📋 **Understanding migration phases**
- 🔧 **Advanced configuration options**  
- 📊 **Migration planning and sizing**

**Re-run Scripts if:**
- 🔄 **Temporary network issues**
- 🔄 **Partial migration failures**
- 🔄 **Configuration changes**

---

## 💡 **Pro Tips for Customers**

1. **Always run Phase 1 first** - it catches 90% of issues
2. **Read the logs** - they contain specific error details
3. **Test with small data** - try a cluster with few users/teams first
4. **Run phases one-by-one** - easier to troubleshoot than full automation
5. **Keep backups** - export destination state before starting

**Remember**: Every error message contains clues. Read them carefully! 