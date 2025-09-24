# ✅ Phase 5: Post-Migration Verification

**Purpose**: Validate migration success and verify system integrity

## 🧪 Scripts in this Phase

### `run_test_suite.sh`
**What it does**: Comprehensive post-migration validation
- Verifies all migrated components are working correctly
- Tests user authentication and team permissions
- Validates environment configurations and applications
- Confirms migration completeness and data integrity

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
./run_test_suite.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"

# Or run via RUN_THIS_PHASE.sh
./RUN_THIS_PHASE.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

## 📋 Verification Areas

### 🔐 **Authentication & Users**
- User login functionality
- Role assignments and permissions
- Identity provider integration (SAML/Azure AD)
- Team memberships and access

### 🏗️ **Environments**
- Environment configurations match source
- Team permissions are correctly assigned
- Policies and settings are preserved
- Cluster associations are correct

### 📱 **Applications**
- Catalog applications are accessible
- Application references are updated
- Git credentials are working
- Application deployments are functional

### 🔍 **Data Integrity**
- No missing components
- Cross-references are intact
- Metadata is preserved
- Audit trails are complete

## ✅ Success Criteria

Phase 5 is successful when:
- All verification tests pass (≥90% success rate)
- Critical components are fully functional
- No data corruption or missing elements
- Users can access destination environment successfully

## 📋 Expected Output

```
✅ Phase 5: Post-Migration Verification Complete!

📊 Test Results Summary:
   📋 Phase 1: Pre-migration validation ✅
   👥 Phase 2: User & team migration ✅  
   🏗️ Phase 3: Environment migration ✅
   📱 Phase 4: Application migration ✅
   ✅ Phase 5: Post-migration verification ✅

🎯 Migration Success Rate: 100%
✅ All critical components verified
✅ System ready for production use
```

## ⚠️ Common Issues

- **Authentication failures**: Users may need to reset passwords (Local auth)
- **Permission mismatches**: Teams may need additional role assignments
- **Application access issues**: Git credentials or catalog permissions
- **Environment configuration drift**: Manual adjustments may be needed

## 🔧 Troubleshooting

If verification fails:
1. **Review logs**: Check `../../06-logs/` for detailed error information
2. **Re-run specific phases**: Address issues in earlier phases if needed
3. **Manual verification**: Test critical functionality manually in destination UI
4. **Contact support**: For complex issues or platform-specific problems

## 🎉 Migration Complete!

If Phase 5 passes, your cross-environment migration is complete! 

### 📋 Next Steps:
1. **User notification**: Inform users about the new environment
2. **DNS/URL updates**: Update any hardcoded references to new environment
3. **Monitoring setup**: Configure monitoring for the new environment
4. **Backup verification**: Ensure backup processes are working
5. **Documentation update**: Update internal documentation with new environment details

## 🔍 Manual Verification Commands

### Check Migrated Users
```bash
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/users/api/users" | jq '.[] | {email: .email, role: .role, identityProvider: .identityProvider}'
```

### Check Migrated Teams
```bash
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/users/api/teams" | jq '.[] | {name: .name, userCount: (.users | length)}'
```

### Check Migrated Environments
```bash
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/environments/api/environments" | jq '.[] | {name: .name, cluster: .cluster.name}'
```

### Check Catalog Applications
```bash
curl -s -H "Authorization: NIRMATA-API $DEST_TOKEN" \
  "$DEST_API/catalog/api/catalogapplications" | jq '.[] | {name: .name, gitRepo: .gitRepo}'
```

## 📋 Post-Migration Checklist

- [ ] All users can log in to destination environment
- [ ] Teams have correct members and permissions
- [ ] Environments are accessible and functional
- [ ] Applications can be deployed successfully
- [ ] Git credentials are working
- [ ] SAML/Azure AD authentication works (if applicable)
- [ ] Migration logs archived for audit purposes 