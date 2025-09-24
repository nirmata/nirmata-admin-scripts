# 📋 Phase 1: Pre-Migration Validation

**Purpose**: Validate environments and test compatibility before starting migration

## 🧪 Scripts in this Phase

### `run_test_suite.sh`
**What it does**: Comprehensive pre-migration testing
- Tests API connectivity to both environments
- Validates authentication tokens
- Checks user roles and permissions
- Verifies identity provider compatibility
- Tests team structure compatibility

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

### `test_identity_provider_compatibility.sh`
**What it does**: Specific identity provider compatibility testing
- Checks SAML configuration support
- Tests Azure AD compatibility
- Validates Local authentication fallback

**Arguments**: Same 6 arguments as above

**Usage**:
```bash
./test_identity_provider_compatibility.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

### `simulate_perfect_migration.sh`
**What it does**: Dry run simulation of entire migration
- Tests all migration steps without making changes
- Identifies potential issues before actual migration
- Provides migration preview and estimates

**Arguments**: Same 6 arguments as above

**Usage**:
```bash
./simulate_perfect_migration.sh \
  "https://source.nirmata.co" "SOURCE_TOKEN" "source-cluster" \
  "https://destination.nirmata.co" "DEST_TOKEN" "dest-cluster"
```

## ✅ Success Criteria

Phase 1 is successful when:
- All connectivity tests pass
- Authentication is verified for both environments
- Identity provider compatibility is confirmed
- No critical errors are found in simulation

## ⚠️ Common Issues

- **Authentication failures**: Check API tokens and permissions
- **Network connectivity**: Verify firewall rules and DNS resolution
- **Identity provider mismatches**: Configure SAML/Azure AD in destination
- **Permission issues**: Ensure tokens have required privileges

## 📋 Next Steps

After Phase 1 succeeds, proceed to:
**Phase 2**: `../phase2-users-teams/` 