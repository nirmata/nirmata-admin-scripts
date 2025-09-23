# 🔄 Kubernetes Image Migration Rollback Guide

## 🎯 **Complete Rollback Solution**

This guide covers the comprehensive rollback functionality for the Kubernetes Image Migration Tool, ensuring you can safely revert any migration if needed.

---

## 📋 **Rollback Components**

### **1. Automatic Rollback Backup**
- **Created automatically** during every migration (non-dry-run)
- **Timestamped files** for easy identification
- **Complete audit trail** for rollback operations

### **2. Dedicated Rollback Script**
- **`k8s-image-rollback.sh`** - Standalone rollback tool
- **CSV-driven rollback** using migration audit files
- **Same safety features** as migration script (dry-run, interactive)

---

## 🚀 **How Rollback Works**

### **Step 1: Migration Creates Rollback Data**
```bash
# During migration, automatic rollback backup is created
./k8s-image-migration.sh \
  --namespace production \
  --source-registry docker-repo.nibr.novartis.net \
  --dest-registry artifactory.f1.novartis.net/to-ddi-diu-zephyr-docker \
  --output-csv production-migration.csv

# Output includes:
# ✅ production-migration.csv (audit trail)
# ✅ production-migration_rollback_20250923_090553.csv (automatic backup)
```

### **Step 2: Rollback Uses Migration Data**
```bash
# Rollback using the automatic backup file
./k8s-image-rollback.sh \
  --csv-file production-migration_rollback_20250923_090553.csv \
  --rollback-csv production-rollback-executed.csv
```

---

## 📊 **Rollback Data Flow**

```
Migration CSV:
┌─────────────────────────────────────────────────────────────────┐
│ Source Image → Destination Image                               │
│ docker-repo.nibr.novartis.net/app:v1 → artifactory.../app:v1  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
Rollback Process:
┌─────────────────────────────────────────────────────────────────┐
│ Current Image ← Original Image                                  │
│ artifactory.../app:v1 ← docker-repo.nibr.novartis.net/app:v1  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ **Rollback Script Usage**

### **Basic Rollback Commands**

#### **1. Dry-Run Rollback (Always Recommended First)**
```bash
./k8s-image-rollback.sh --dry-run \
  --csv-file production-migration-executed.csv \
  --rollback-csv production-rollback-plan.csv
```

#### **2. Interactive Rollback**
```bash
./k8s-image-rollback.sh --interactive \
  --csv-file production-migration-executed.csv \
  --rollback-csv production-rollback-executed.csv
```

#### **3. Namespace-Specific Rollback**
```bash
./k8s-image-rollback.sh \
  --csv-file all-namespaces-migration.csv \
  --namespace production \
  --rollback-csv production-only-rollback.csv
```

#### **4. Full Automatic Rollback**
```bash
./k8s-image-rollback.sh \
  --csv-file production-migration-executed.csv \
  --rollback-csv production-rollback-executed.csv
```

---

## 📋 **Command Reference**

| Option | Description | Example |
|--------|-------------|---------|
| `-f, --csv-file` | Migration CSV file (required) | `--csv-file migration.csv` |
| `-n, --namespace` | Target namespace (optional) | `--namespace production` |
| `--dry-run` | Test rollback without changes | `--dry-run` |
| `-i, --interactive` | Confirm each rollback | `--interactive` |
| `--rollback-csv` | Output rollback audit file | `--rollback-csv rollback.csv` |
| `-v, --verbose` | Enable verbose logging | `--verbose` |
| `-h, --help` | Show help message | `--help` |

---

## 📊 **Rollback CSV Format**

### **Input (Migration CSV)**
```csv
Timestamp,Namespace,Resource Type,Resource Name,Source Image,Destination Image,Source Registry,Destination Registry,Image Pull Secret,Migration Status
2025-09-23 09:00:00,production,deployment,web-app,"legacy-docker-repo.company.net/app/web:v1.0","artifactory.company.net/docker-virtual/app/web:v1.0",legacy-docker-repo.company.net,artifactory.company.net/docker-virtual,artifactory-secret,Executed
```

### **Output (Rollback CSV)**
```csv
Timestamp,Namespace,Resource Type,Resource Name,Current Image,Rollback Image,Action,Status
2025-09-23 09:05:00,production,deployment,web-app,"artifactory.company.net/docker-virtual/app/web:v1.0","legacy-docker-repo.company.net/app/web:v1.0",Rollback,Executed
```

---

## 🎯 **Real-World Rollback Scenarios**

### **Scenario 1: Immediate Rollback After Migration Issues**

```bash
# 1. Migration completed but applications are failing
./k8s-image-migration.sh --namespace production --source-registry old-registry --dest-registry new-registry --output-csv prod-migration.csv
# Result: Applications not starting due to registry issues

# 2. Immediate rollback using automatic backup
./k8s-image-rollback.sh --csv-file prod-migration_rollback_20250923_090000.csv --rollback-csv emergency-rollback.csv
# Result: Applications restored to working state
```

### **Scenario 2: Partial Rollback for Specific Namespace**

```bash
# 1. Multi-namespace migration completed
./k8s-image-migration.sh --namespace staging --source-registry old --dest-registry new --output-csv staging-migration.csv
./k8s-image-migration.sh --namespace production --source-registry old --dest-registry new --output-csv prod-migration.csv

# 2. Production has issues, rollback only production
./k8s-image-rollback.sh --csv-file prod-migration.csv --namespace production --rollback-csv prod-rollback.csv
# Result: Only production rolled back, staging remains migrated
```

### **Scenario 3: Selective Interactive Rollback**

```bash
# 1. Some applications work, others don't after migration
./k8s-image-rollback.sh --interactive --csv-file migration.csv --rollback-csv selective-rollback.csv

# Interactive prompts:
# Rollback deployment/web-frontend in production? (y/n/q): n  # Working fine
# Rollback deployment/api-backend in production? (y/n/q): y   # Has issues
# Rollback deployment/database in production? (y/n/q): n      # Working fine
```

---

## 🔍 **Rollback Validation**

### **Before Rollback**
```bash
# Check current state
kubectl get deployments -n production -o wide
kubectl get pods -n production

# Verify migration CSV exists
ls -la *rollback*.csv
head -5 production-migration_rollback_*.csv
```

### **During Rollback (Dry-Run)**
```bash
# Always test first
./k8s-image-rollback.sh --dry-run --csv-file migration.csv

# Review rollback plan
# Verify image mappings are correct
# Check resource counts match expectations
```

### **After Rollback**
```bash
# Verify images are restored
kubectl get deployments -n production -o wide
kubectl describe deployment web-app -n production

# Check application health
kubectl get pods -n production
kubectl logs -l app=web-app -n production --tail=50
```

---

## ⚠️ **Important Rollback Considerations**

### **✅ What Gets Rolled Back**
- ✅ **Container Images**: Restored to original registry/tags
- ✅ **Init Container Images**: Restored to original registry/tags
- ✅ **All Resource Types**: Deployments, StatefulSets, DaemonSets, Pods, CronJobs, Jobs

### **❌ What Does NOT Get Rolled Back**
- ❌ **ImagePullSecrets**: Left in place for safety (won't break anything)
- ❌ **Pod Names**: New pods get new names (normal Kubernetes behavior)
- ❌ **Other Resource Changes**: Only images are modified

### **🔄 Resource Behavior During Rollback**
- **Deployments**: Rolling update with new pods
- **StatefulSets**: Ordered update of pods
- **DaemonSets**: Update across all nodes
- **Pods**: Direct image update (may cause restart)
- **CronJobs**: Next execution uses original image
- **Jobs**: Existing jobs unchanged, new jobs use original image

---

## 🛡️ **Rollback Safety Features**

### **1. Dry-Run Validation**
```bash
# Always test rollback first
./k8s-image-rollback.sh --dry-run --csv-file migration.csv
```

### **2. Interactive Confirmation**
```bash
# Review each rollback individually
./k8s-image-rollback.sh --interactive --csv-file migration.csv
```

### **3. Namespace Filtering**
```bash
# Rollback only specific namespace
./k8s-image-rollback.sh --csv-file migration.csv --namespace production
```

### **4. Complete Audit Trail**
```bash
# Generate rollback audit CSV
./k8s-image-rollback.sh --csv-file migration.csv --rollback-csv rollback-audit.csv
```

---

## 📈 **Rollback Performance**

| Scenario | Resources | Estimated Time | Notes |
|----------|-----------|----------------|-------|
| **Small Deployment** | 1-5 resources | < 30 seconds | Fast rollback |
| **Medium Application** | 5-20 resources | 1-3 minutes | Includes rolling updates |
| **Large Namespace** | 20-100 resources | 5-15 minutes | Depends on pod startup time |
| **Critical Applications** | Any size | + Health check time | Wait for application readiness |

---

## 🚨 **Emergency Rollback Procedure**

### **Quick Emergency Rollback**
```bash
# 1. Find the latest migration backup
ls -la *rollback*.csv | tail -1

# 2. Execute immediate rollback
./k8s-image-rollback.sh --csv-file <latest-rollback-file> --rollback-csv emergency-rollback.csv

# 3. Monitor application recovery
kubectl get pods -n <namespace> -w
```

### **Emergency Rollback Checklist**
- [ ] Identify the migration CSV file
- [ ] Run rollback dry-run if time permits
- [ ] Execute rollback with audit trail
- [ ] Monitor pod status and application health
- [ ] Verify applications are functional
- [ ] Document the incident and rollback

---

## 🎯 **Best Practices**

### **1. Always Keep Migration CSV Files**
- Store migration CSV files securely
- Include timestamp in filenames
- Keep backups of rollback CSV files

### **2. Test Rollback in Non-Production**
- Practice rollback procedures in staging
- Validate rollback scripts work correctly
- Time the rollback process

### **3. Monitor During Rollback**
- Watch pod status during rollback
- Check application logs for errors
- Verify application functionality post-rollback

### **4. Document Rollback Decisions**
- Record why rollback was needed
- Document which resources were rolled back
- Keep audit trail for compliance

---

## 🏆 **Rollback Success Criteria**

### **✅ Successful Rollback Indicators**
- All targeted resources show original images
- Pods are running and healthy
- Applications respond correctly
- No error logs related to image pulls
- Rollback audit CSV generated

### **❌ Rollback Issues to Watch For**
- Pods stuck in ImagePullBackOff
- Applications not starting correctly
- Missing imagePullSecrets for original registry
- Network connectivity to original registry

---

## 📞 **Troubleshooting Rollback Issues**

### **Issue: Pods Can't Pull Original Images**
```bash
# Check if original registry is accessible
kubectl run test-pod --image=docker-repo.nibr.novartis.net/test:latest --rm -it -- /bin/sh

# Verify imagePullSecrets exist for original registry
kubectl get secrets -n <namespace> | grep docker-registry
```

### **Issue: Some Resources Not Found**
```bash
# This is normal for pods that were recreated during migration
# Focus on persistent resources (Deployments, StatefulSets, etc.)
# Check deployment status instead of individual pods
kubectl get deployments -n <namespace>
```

### **Issue: Rollback CSV Shows Wrong Images**
```bash
# Verify the migration CSV file is correct
head -5 migration.csv
# Check if you're using the right CSV file
# Ensure CSV format matches expected structure
```

---

## 🎉 **Rollback Complete!**

Your Kubernetes Image Migration Tool now includes comprehensive rollback capabilities:

- ✅ **Automatic Backup Creation** during migration
- ✅ **Dedicated Rollback Script** with full feature set
- ✅ **Complete Audit Trail** for compliance
- ✅ **Safety Features** (dry-run, interactive, namespace filtering)
- ✅ **Production-Ready** rollback procedures

**You can now migrate with confidence, knowing you have a reliable rollback path!** 🚀
