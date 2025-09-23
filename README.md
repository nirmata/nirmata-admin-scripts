# Nirmata Admin Scripts

This repository contains essential administrative scripts and utilities for Nirmata platform management and Kubernetes operations.

## 📁 Repository Structure

### 🔄 [kubernetes-image-migration/](kubernetes-image-migration/)
Production-ready Kubernetes container image migration tool with comprehensive features:

- **Granular Control**: Migrate specific namespaces only
- **Dry-Run Support**: Test migrations without making changes
- **Complete Audit Trail**: CSV and JSON export for compliance
- **Rollback Capabilities**: Automatic backup and rollback functionality
- **Multiple Registry Support**: JFrog Artifactory, GitHub Container Registry, and more

#### Key Features
- ✅ **Safe Migration**: Dry-run and interactive modes
- ✅ **Comprehensive Logging**: Detailed audit trails
- ✅ **Production Ready**: Extensively tested and validated
- ✅ **Rollback Support**: Complete rollback functionality
- ✅ **Multi-Resource Support**: Deployments, StatefulSets, DaemonSets, Pods, CronJobs, Jobs

#### Quick Start
```bash
cd kubernetes-image-migration

# 1. Create imagePullSecret first
kubectl create secret docker-registry artifactory-secret \
  --docker-server=your-registry.company.net \
  --docker-username=your-username \
  --docker-password=your-password \
  --namespace=production

# 2. Run dry-run migration
./k8s-image-migration.sh --dry-run \
  --namespace production \
  --source-registry old-registry.company.net \
  --dest-registry new-registry.company.net \
  --output-csv migration-audit.csv

# 3. Execute migration after reviewing the plan
./k8s-image-migration.sh \
  --namespace production \
  --source-registry old-registry.company.net \
  --dest-registry new-registry.company.net \
  --output-csv migration-executed.csv
```

See the [kubernetes-image-migration README](kubernetes-image-migration/README.md) for complete documentation.

---

## 🛠️ Other Admin Scripts

### Scripts
- **nirmata_test.sh** - Comprehensive health check and testing script for Nirmata environments
- **cleanup-cluster.sh** - Script to clean up Kubernetes clusters
- **cleanup-cluster-agent.sh** - Script to clean up Nirmata cluster agents

### Directories
- **ndp_application_migration/** - Scripts and utilities for migrating applications in NDP (Nirmata DevSecOps Platform)
- **environment_permissions/** - Scripts for managing and checking environment permissions
- **backup-restore/** - Scripts for backup and restore operations of Nirmata components
- **validate-kyverno/** - Scripts and utilities for validating Kyverno policies and health checks
- **cross_environment_migration/** - Complete workflow scripts for cross-environment migration operations
- **collect-nirmata-services-logs/** - Scripts for collecting Nirmata service logs and diagnostics

## 📖 Usage

Each script and directory contains its own documentation. Please refer to individual README files where available for specific usage instructions.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all scripts are tested before submission
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 📞 Support

For issues, questions, or contributions:
1. Check the documentation in each tool's directory
2. Review existing issues in the GitHub repository
3. Create a new issue with detailed information
4. Include relevant logs and configuration details

---

*Maintained by the Nirmata Team*