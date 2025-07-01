# ✅ Phase 5: Post-Migration Verification

**Purpose**: Validate migration success and ensure data integrity

## ✅ Scripts in this Phase

### `run_test_suite.sh`
**What it does**: Comprehensive post-migration validation
- Validates user and team migration success
- Checks role preservation accuracy
- Verifies environment configuration integrity
- Tests application functionality and references
- Generates migration success report

**Usage**:
```bash
./run_test_suite.sh --mode=post-migration
```

## 🧪 What Gets Validated

### User & Team Verification
- All users migrated successfully
- User roles preserved correctly (admin, devops, etc.)
- Identity providers handled properly
- Team memberships intact

### Environment Verification
- Environment configurations copied correctly
- Team role bindings preserved
- Policies and settings maintained
- No configuration drift

### Application Verification
- Git-based applications converted to catalog
- Application references updated correctly
- Catalog applications functional
- No broken dependencies

## ✅ Success Criteria

Phase 5 is successful when:
- All validation tests pass
- No critical migration errors found
- Data integrity is confirmed
- All components are functional

## 📋 Expected Output

```
✅ Test 1: Authentication validation - PASSED
✅ Test 2: User role preservation - PASSED  
✅ Test 3: Team creation validation - PASSED
✅ Test 4: Identity provider compatibility - PASSED
✅ Test 5: Environment integrity - PASSED
✅ Test 6: Application migration - PASSED
✅ Test 7: Catalog references - PASSED

🎉 Test Results: 10/10 tests passed (100%)

📊 Migration Summary:
👥 Users migrated: 15/15 (100%)
🏷️  Teams created: 4/4 (100%)
🏗️  Environments: 7/7 (100%)
📱 Applications: 18/25 (72% - 7 skipped non-Git apps)
```

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

## ⚠️ Common Issues

- **Test failures**: Some components may not have migrated correctly
- **Data inconsistencies**: Source and destination don't match
- **Functional issues**: Applications or environments not working properly
- **Permission problems**: Users can't access expected resources

## 🔧 Troubleshooting

### Test Failures
1. Check detailed logs in `06-logs/` directory
2. Re-run specific migration phases that failed
3. Verify source and destination configurations

### Data Inconsistencies
1. Compare source vs destination manually
2. Check for API rate limiting or timeout issues
3. Verify all prerequisites were met

### Functional Issues
1. Test application deployments manually
2. Verify Git credentials are working
3. Check team permissions in destination UI

## 📊 Migration Report

After successful verification, you'll have:
- **Complete audit trail** in log files
- **Migration statistics** showing success rates
- **Issue summary** with any warnings or errors
- **Recommendations** for post-migration steps

## 🎉 Migration Complete!

After Phase 5 succeeds:
1. **Review logs** in `06-logs/` for any warnings
2. **Verify in UI** - Check destination Nirmata interface
3. **Test functionality** - Deploy applications to verify end-to-end
4. **Update documentation** - Record any environment-specific changes
5. **Communicate success** - Notify stakeholders of completion

## 📋 Post-Migration Checklist

- [ ] All users can log in to destination environment
- [ ] Teams have correct members and permissions
- [ ] Environments are accessible and functional
- [ ] Applications can be deployed successfully
- [ ] Git credentials are working
- [ ] SAML/Azure AD authentication works (if applicable)
- [ ] Migration logs archived for audit purposes 