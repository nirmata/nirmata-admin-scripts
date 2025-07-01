# User and Team Migration Scripts

This directory contains scripts for migrating users and teams between different Nirmata environments, specifically designed to copy only the teams and users that are associated with a specific cluster through environments and catalogs.

## Use Case
Use these scripts when you need to migrate users and teams from one Nirmata environment to another, but only want to migrate those that are actually being used in a specific cluster.

**Example Scenario:**
- Source: `source.nirmata.co` with cluster `source-cluster`
- Destination: `destination.nirmata.co` with cluster `dest-cluster`
- Goal: Copy only teams/users that have permissions in the source cluster

## How It Works

### Team Discovery Process
The script identifies teams to migrate by analyzing:

1. **Environment Role Bindings**: Teams that have permissions in environments within the specified cluster
2. **Catalog Permissions**: Teams that have permissions on catalogs in the source environment
3. **Cluster Association**: Only teams associated with the specified source cluster are considered

### Migration Process
For each discovered team:

1. **Team Creation**: Creates the team in the destination environment (if it doesn't exist)
2. **User Invitation**: Invites users to the destination environment (if they don't exist)
3. **Team Membership**: Adds users to their respective teams in the destination environment

## Scripts

### `copy_users_teams_cross_env.sh`
Main migration script that handles the entire process.

**Usage:**
```bash
./copy_users_teams_cross_env.sh \
    <source_api_endpoint> <source_token> <source_cluster_name> \
    <dest_api_endpoint> <dest_token> <dest_cluster_name>
```

**Example:**
```bash
./copy_users_teams_cross_env.sh \
    "https://source.nirmata.co" \
    "YOUR_SOURCE_TOKEN_HERE" \
    "source-cluster" \
    "https://destination.nirmata.co" \
    "YOUR_DESTINATION_TOKEN_HERE" \
    "dest-cluster"
```

### `run_user_team_migration_example.sh`
Pre-configured example script with your specific environment details.

**Usage:**
```bash
./run_user_team_migration_example.sh
```

This script uses the following configuration:
- **Source**: `source.nirmata.co` (cluster: `source-cluster`)
- **Destination**: `destination.nirmata.co` (cluster: `dest-cluster`)

## Prerequisites

- `curl` installed
- `jq` installed
- Bash shell
- Valid API tokens for both source and destination environments
- Network access to both API endpoints
- Appropriate permissions to:
  - Read teams, users, environments, and catalogs in source
  - Create teams and invite users in destination

## What Gets Migrated

### Teams
- Team name and description
- Only teams that have permissions in the specified cluster
- Teams are created in destination if they don't exist
- Existing teams are skipped (no duplicates)

### Users
- User email and name
- Users are invited to destination if they don't exist
- Existing users are skipped (no duplicate invitations)
- Users are added to their respective teams

### What's NOT Migrated
- User passwords or authentication details
- Team permissions/role bindings (use the main migration scripts for this)
- Users not associated with any team in the source cluster
- Teams without any association to the source cluster

## Important Notes

### User Invitations
- New users will receive email invitations to join the destination environment
- Users must accept the invitation to complete their account setup
- Existing users will not receive new invitations

### Team Permissions
- This script only creates teams and adds users to them
- It does NOT migrate the actual permissions/role bindings
- Use the main environment migration scripts to copy permissions after running this script

### Duplicate Handling
- Teams with the same name in destination are skipped
- Users with the same email in destination are skipped
- Users already in teams are not re-added

## Logging

All operations are logged to: `06-logs/user_team_migration_<source_cluster>_to_<dest_cluster>_<timestamp>.log`

The log includes:
- Authentication status
- Teams discovered and their sources
- Users processed for each team
- Success/failure status for each operation
- Detailed error messages for troubleshooting

## Verification Steps

After running the migration:

1. **Check Destination Environment**:
   - Log into the destination Nirmata environment
   - Verify teams were created under "Access Control" → "Teams"
   - Check that users are listed in their respective teams

2. **User Acceptance**:
   - New users should check their email for invitations
   - Users need to accept invitations to complete setup

3. **Review Logs**:
   - Check the log file for any errors or warnings
   - Verify all expected teams and users were processed

## Troubleshooting

### Common Issues

1. **Authentication Failed**:
   - Verify API tokens are correct and have proper permissions
   - Check network connectivity to both environments

2. **Teams Not Found**:
   - Ensure the source cluster name is correct
   - Verify teams actually have permissions in the cluster environments

3. **User Invitation Failed**:
   - Check if user email addresses are valid
   - Verify destination environment allows user invitations

4. **Permission Denied**:
   - Ensure API tokens have sufficient permissions
   - Check that you can create teams and invite users in destination

### Debug Steps

1. Check the detailed log file for specific error messages
2. Verify cluster names exist in both environments
3. Test API connectivity manually using curl
4. Ensure both environments are accessible and operational

## Security Considerations

- API tokens are sensitive - handle them securely
- Log files may contain user email addresses - protect accordingly
- Users will receive email invitations - ensure proper communication
- Consider running in test mode first to verify expected behavior

## Integration with Main Migration Scripts

This script is designed to be used alongside the main cross-environment migration scripts:

1. **First**: Run this user/team migration script
2. **Then**: Run the main environment migration scripts to copy permissions and applications

This ensures that teams and users exist before trying to assign them permissions in the destination environment. 