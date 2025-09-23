# Updated Kubernetes Image Migration Tool - Enhanced Granularity & CSV Auditing

## 🎯 Key Updates Based on Your Requirements

### ✅ **Namespace Granularity**
- **REQUIRED**: You must now specify a namespace with `-n` or `--namespace`
- **NO MORE "ALL" NAMESPACES**: Script only operates on the specific namespace you provide
- **Precise Control**: Migrate exactly what you want, when you want

### ✅ **CSV Audit Output**
- **NEW**: `--output-csv` parameter for audit trail
- **Comprehensive**: Includes timestamp, all migration details, and status
- **Excel/Spreadsheet Ready**: Perfect for compliance and auditing

## 🚀 Updated Usage Examples

### **1. Enterprise JFrog Migration**
```bash
# Dry-run with CSV audit for production namespace
./k8s-image-migration.sh --dry-run \
  --namespace production \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --output-csv production-migration-audit.csv

# After reviewing, execute actual migration
./k8s-image-migration.sh \
  --namespace production \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --output-csv production-migration-executed.csv
```

### **2. Namespace-by-Namespace Migration**
```bash
# Migrate development namespace first
./k8s-image-migration.sh \
  --namespace development \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --output-csv dev-migration-audit.csv

# Then staging namespace
./k8s-image-migration.sh \
  --namespace staging \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --output-csv staging-migration-audit.csv

# Finally production namespace
./k8s-image-migration.sh \
  --namespace production \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --output-csv production-migration-audit.csv
```

### **3. Interactive Migration with Audit**
```bash
# Interactive mode for careful migration with CSV audit
./k8s-image-migration.sh --interactive \
  --namespace critical-apps \
  --source-registry legacy-docker-repo.company.net \
  --dest-registry artifactory.company.net/docker-virtual \
  --output-csv critical-apps-migration-audit.csv
```

## 📊 CSV Audit Output Format

The CSV file contains the following columns for complete audit trail:

| Column | Description | Example |
|--------|-------------|---------|
| **Timestamp** | When the migration plan was created | `2025-09-23 08:51:12` |
| **Namespace** | Target namespace | `production` |
| **Resource Type** | Kubernetes resource type | `deployment`, `statefulset`, `pod` |
| **Resource Name** | Name of the resource | `web-frontend`, `api-backend` |
| **Source Image** | Original image path | `legacy-docker-repo.company.net/app/web:v1.0` |
| **Destination Image** | New image path | `artifactory.company.net/docker-virtual/app/web:v1.0` |
| **Source Registry** | Source registry domain | `legacy-docker-repo.company.net` |
| **Destination Registry** | Destination registry domain | `artifactory.company.net/docker-virtual` |
| **Image Pull Secret** | ImagePullSecret used | `artifactory-secret` |
| **Migration Status** | Current status | `Planned`, `Completed`, `Failed` |

### **Sample CSV Output**
```csv
Timestamp,Namespace,Resource Type,Resource Name,Source Image,Destination Image,Source Registry,Destination Registry,Image Pull Secret,Migration Status
2025-09-23 08:51:12,production,deployment,web-frontend,"legacy-docker-repo.company.net/app/web:v1.0","artifactory.company.net/docker-virtual/app/web:v1.0",legacy-docker-repo.company.net,artifactory.company.net/docker-virtual,artifactory-secret,Planned
2025-09-23 08:51:12,production,deployment,api-backend,"legacy-docker-repo.company.net/app/api:v2.1","artifactory.company.net/docker-virtual/app/api:v2.1",legacy-docker-repo.company.net,artifactory.company.net/docker-virtual,artifactory-secret,Planned
2025-09-23 08:51:12,production,statefulset,database,"legacy-docker-repo.company.net/db/postgres:13","artifactory.company.net/docker-virtual/db/postgres:13",legacy-docker-repo.company.net,artifactory.company.net/docker-virtual,artifactory-secret,Planned
```

## 🔒 Enhanced Security & Control

### **Namespace Validation**
```bash
# This will now FAIL - namespace is required
./k8s-image-migration.sh --source-registry old-registry --dest-registry new-registry
# ERROR: Namespace is required. Use -n or --namespace to specify target namespace

# This works - specific namespace provided
./k8s-image-migration.sh --namespace production --source-registry old-registry --dest-registry new-registry
```

### **No Accidental Cluster-Wide Changes**
- **Before**: Could accidentally migrate all namespaces
- **Now**: Only migrates the specific namespace you specify
- **Safety**: Prevents unintended changes to system or other application namespaces

## 📋 Updated Command Reference

### **Required Parameters**
```bash
-n, --namespace NAMESPACE       Target namespace (REQUIRED)
-s, --source-registry REGISTRY Source registry to migrate from (REQUIRED)
-d, --dest-registry REGISTRY   Destination registry to migrate to (REQUIRED)
```

### **Optional Parameters**
```bash
-p, --image-pull-secret SECRET ImagePullSecret name (default: artifactory-secret)
--dry-run                      Perform dry run without changes
-i, --interactive              Ask for confirmation before each migration
-o, --output-plan FILE         Output migration plan to JSON file
--output-csv FILE              Output migration plan to CSV file for auditing
-v, --verbose                  Enable verbose logging
-h, --help                     Show help message
```

## 🎯 Real-World Migration Workflow

### **Step 1: Plan & Audit**
```bash
# Create migration plan with CSV audit
./k8s-image-migration.sh --dry-run \
  --namespace production \
  --source-registry docker-repo.nibr.novartis.net \
  --dest-registry artifactory.f1.novartis.net/to-ddi-diu-zephyr-docker \
  --output-csv production-migration-plan.csv
```

### **Step 2: Review CSV File**
- Open `production-migration-plan.csv` in Excel/Google Sheets
- Review all images to be migrated
- Verify source → destination mappings
- Share with team for approval

### **Step 3: Execute Migration**
```bash
# Execute actual migration with audit trail
./k8s-image-migration.sh \
  --namespace production \
  --source-registry docker-repo.nibr.novartis.net \
  --dest-registry artifactory.f1.novartis.net/to-ddi-diu-zephyr-docker \
  --output-csv production-migration-executed.csv
```

### **Step 4: Post-Migration Verification**
```bash
# Verify all images are updated
kubectl get deployments,statefulsets,daemonsets -n production -o wide

# Check imagePullSecrets are added
kubectl get deployment <name> -n production -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}'
```

## 📊 Audit Benefits

### **Compliance Ready**
- **Timestamp**: When migration was planned/executed
- **Traceability**: Complete before/after image mapping
- **Accountability**: Clear record of what was changed

### **Excel Integration**
- **Filtering**: Filter by namespace, resource type, or status
- **Sorting**: Sort by timestamp or resource name
- **Reporting**: Create charts and summaries
- **Sharing**: Easy to share with stakeholders

### **Change Management**
- **Documentation**: Permanent record of migration
- **Rollback Planning**: Clear mapping for potential rollbacks
- **Impact Analysis**: Understand scope of changes

## 🚀 Your Migration is Now:

✅ **Granular**: Target specific namespaces only  
✅ **Auditable**: Complete CSV trail for compliance  
✅ **Safe**: Dry-run validation before execution  
✅ **Controlled**: Interactive mode for careful migration  
✅ **Documented**: Permanent record of all changes  

Perfect for your enterprise JFrog migration requirements!
