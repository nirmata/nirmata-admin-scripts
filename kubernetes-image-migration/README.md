# Kubernetes Image Migration Tool

A comprehensive bash script for migrating container images in Kubernetes clusters with granular control, dry-run support, and automatic imagePullSecrets management.

## 🚀 Features

- **Granular Control**: Migrate specific namespaces only
- **Dry-Run Support**: Test migrations without making actual changes
- **Interactive Mode**: Confirm each migration individually
- **imagePullSecrets Management**: Automatically add imagePullSecrets if missing
- **Multiple Resource Types**: Supports Deployments, StatefulSets, DaemonSets, Pods, CronJobs, and Jobs
- **Comprehensive Logging**: Colored output with verbose mode
- **CSV Audit Trail**: Complete audit trail for compliance
- **JSON Export**: Save migration plans to JSON files
- **Rollback Support**: Complete rollback functionality with automatic backup creation

## 📋 Prerequisites

- `kubectl` configured and connected to your cluster
- `jq` for JSON processing
- Bash 4.0+ (for associative arrays)

## 🛠️ Installation

```bash
# Clone the repository
git clone <repository-url>
cd kubernetes-image-migration

# Make scripts executable
chmod +x k8s-image-migration.sh
chmod +x k8s-image-rollback.sh
```

## 📖 Usage

### Basic Migration

```bash
# Dry run migration for specific namespace with CSV output
./k8s-image-migration.sh --dry-run \
  --namespace production \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --output-csv migration-audit.csv

# Execute migration after review
./k8s-image-migration.sh \
  --namespace production \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --output-csv migration-executed.csv
```

### Interactive Migration

```bash
# Interactive migration with confirmation for each resource
./k8s-image-migration.sh --interactive \
  --namespace production \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual
```

### Rollback

```bash
# Rollback using migration CSV file
./k8s-image-rollback.sh \
  --csv-file migration-executed.csv \
  --rollback-csv rollback-audit.csv
```

## 📊 Command Line Options

### Migration Script (`k8s-image-migration.sh`)

| Option | Description | Default |
|--------|-------------|---------|
| `-n, --namespace` | Target namespace (required) | None |
| `-s, --source-registry` | Source registry to migrate from (required) | None |
| `-d, --dest-registry` | Destination registry to migrate to (required) | None |
| `-p, --image-pull-secret` | ImagePullSecret name to add | `artifactory-secret` |
| `--dry-run` | Perform dry run without making changes | `false` |
| `-i, --interactive` | Ask for confirmation before each migration | `false` |
| `-o, --output-plan` | Output migration plan to JSON file | None |
| `--output-csv` | Output migration plan to CSV file for auditing | None |
| `-v, --verbose` | Enable verbose logging | `false` |
| `-h, --help` | Show help message | N/A |

### Rollback Script (`k8s-image-rollback.sh`)

| Option | Description | Default |
|--------|-------------|---------|
| `-f, --csv-file` | Migration CSV file to use for rollback (required) | None |
| `-n, --namespace` | Target namespace (optional) | All from CSV |
| `--dry-run` | Perform dry run without making changes | `false` |
| `-i, --interactive` | Ask for confirmation before each rollback | `false` |
| `--rollback-csv` | Output rollback audit CSV file | None |
| `-v, --verbose` | Enable verbose logging | `false` |
| `-h, --help` | Show help message | N/A |

## 🎯 Examples

### Enterprise JFrog Migration

```bash
# Migrate from legacy registry to JFrog Artifactory
./k8s-image-migration.sh --dry-run \
  --namespace production \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --image-pull-secret artifactory-secret \
  --output-csv production-migration-audit.csv
```

### GitHub Container Registry Migration

```bash
# Migrate to GitHub Container Registry
./k8s-image-migration.sh \
  --namespace application \
  --source-registry old-registry.company.net \
  --dest-registry ghcr.io/myorganization \
  --image-pull-secret ghcr-secret \
  --output-csv github-migration.csv
```

### Multi-Namespace Migration

```bash
# Migrate multiple namespaces sequentially
for ns in development staging production; do
  ./k8s-image-migration.sh \
    --namespace $ns \
    --source-registry old-registry.company.net \
    --dest-registry new-registry.company.net \
    --output-csv ${ns}-migration.csv
done
```

## 📊 CSV Audit Trail

The tool generates comprehensive CSV audit trails with the following columns:

- **Timestamp**: When the migration was planned/executed
- **Namespace**: Target Kubernetes namespace
- **Resource Type**: Type of Kubernetes resource (deployment, statefulset, etc.)
- **Resource Name**: Name of the specific resource
- **Source Image**: Original container image
- **Destination Image**: New container image after migration
- **Source Registry**: Source registry domain
- **Destination Registry**: Destination registry domain
- **Image Pull Secret**: ImagePullSecret used for authentication
- **Migration Status**: Current status (Planned, Executed, Failed)

## 🔄 Rollback Support

The tool includes comprehensive rollback functionality:

### Automatic Rollback Backup
- Automatically creates rollback CSV files during migration
- Timestamped files for easy identification
- Complete audit trail for rollback operations

### Rollback Execution
```bash
# Find the rollback backup file
ls -la *rollback*.csv

# Execute rollback
./k8s-image-rollback.sh \
  --csv-file migration_rollback_20240923_090553.csv \
  --rollback-csv rollback-executed.csv
```

## 🛡️ Safety Features

### Dry-Run Mode
Always test your migrations first:
```bash
./k8s-image-migration.sh --dry-run \
  --namespace production \
  --source-registry old-registry \
  --dest-registry new-registry
```

### Interactive Mode
Review each migration individually:
```bash
./k8s-image-migration.sh --interactive \
  --namespace production \
  --source-registry old-registry \
  --dest-registry new-registry
```

### Namespace Isolation
- Only operates on the specified namespace
- No accidental cluster-wide changes
- Granular control over migration scope

## 🧪 Testing

The repository includes comprehensive test suites:

```bash
# Run migration tests
./test-suite.sh

# Run rollback tests
./test-rollback.sh
```

## 📚 Documentation

- **[UPDATED_USAGE.md](UPDATED_USAGE.md)**: Enhanced usage guide with examples
- **[ROLLBACK_GUIDE.md](ROLLBACK_GUIDE.md)**: Complete rollback procedures
- **[PRODUCTION_READINESS_REPORT.md](PRODUCTION_READINESS_REPORT.md)**: Production validation report
- **[EXAMPLE_OUTPUTS.md](EXAMPLE_OUTPUTS.md)**: Real example outputs and scenarios

## 🔧 Supported Resource Types

- **Deployments**: Updates containers and initContainers in pod templates
- **StatefulSets**: Updates containers and initContainers in pod templates
- **DaemonSets**: Updates containers and initContainers in pod templates
- **Pods**: Updates containers and initContainers directly
- **CronJobs**: Updates containers and initContainers in job templates
- **Jobs**: Updates containers and initContainers in pod templates

## 🚨 ImagePullSecrets Management

The script automatically:
- Checks if the specified imagePullSecret exists in each namespace
- Adds the imagePullSecret to resources that don't have it
- Preserves existing imagePullSecrets when adding new ones
- Warns if the imagePullSecret doesn't exist in the namespace

### Creating ImagePullSecrets

```bash
# Create imagePullSecret for Docker registry
kubectl create secret docker-registry my-registry-secret \
  --docker-server=registry.company.net \
  --docker-username=<username> \
  --docker-password=<password> \
  --namespace=<target-namespace>

# Create imagePullSecret for GitHub Container Registry
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-token> \
  --namespace=<target-namespace>
```

## ⚠️ Important Notes

### Before Migration
1. **Always run dry-run first** to validate the migration plan
2. **Backup your cluster** or have a rollback plan ready
3. **Test in non-production environments** first
4. **Ensure destination registry is accessible** from your cluster
5. **Create imagePullSecrets** in target namespaces

### During Migration
1. **Monitor pod status** during the migration process
2. **Check application logs** for any issues
3. **Verify image pull success** on all nodes
4. **Keep migration CSV files** for audit and rollback purposes

### After Migration
1. **Verify all applications are running** correctly
2. **Test application functionality** thoroughly
3. **Monitor for any image pull errors**
4. **Keep rollback files** for emergency recovery

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues, questions, or contributions:
1. Check the documentation in the `docs/` directory
2. Review existing issues in the GitHub repository
3. Create a new issue with detailed information
4. Include relevant logs and configuration details

## 🏆 Production Ready

This tool has been thoroughly tested and is production-ready with:
- ✅ Comprehensive error handling
- ✅ Complete audit trail
- ✅ Safety features (dry-run, interactive)
- ✅ Rollback capabilities
- ✅ Performance optimization
- ✅ Extensive testing coverage

Deploy with confidence for your enterprise container registry migrations!
