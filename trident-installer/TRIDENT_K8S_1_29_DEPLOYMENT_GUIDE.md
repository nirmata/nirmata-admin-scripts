# Trident Deployment Guide for Kubernetes 1.29

## ✅ Verified Success on Kubernetes 1.29.12

This guide provides the complete steps to deploy Trident 25.02.0 on Kubernetes 1.29 managed clusters (like Nirmata managed clusters).

## Prerequisites

- Kubernetes 1.29.x cluster
- Cluster admin privileges
- Access to container registries (NetApp official images)

## Step-by-Step Deployment

### Step 1: Verify Cluster and Prerequisites

```bash
# Check Kubernetes version
kubectl version --short

# Verify cluster admin privileges
kubectl auth can-i '*' '*' --all-namespaces

# Expected output: yes
```

### Step 2: Create Trident Namespace

```bash
kubectl create namespace trident
```

### Step 3: Create TridentOrchestrator CRD

```bash
kubectl create -f deploy/crds/trident.netapp.io_tridentorchestrators_crd_post1.16.yaml
```

### Step 4: Deploy Trident Operator

```bash
# Deploy operator with NetApp official image
kubectl apply -f deploy/operator.yaml

# Wait for operator to be ready
kubectl wait --for=condition=available deployment/trident-operator -n trident --timeout=120s
```

### Step 5: Deploy TridentOrchestrator

```bash
# Apply the K8s 1.29 optimized configuration
kubectl apply -f deploy/crds/tridentorchestrator_cr_k8s_1_29.yaml

# Monitor deployment
kubectl get tridentorchestrator trident -w
```

### Step 6: Verify Installation

```bash
# Check TridentOrchestrator status
kubectl get tridentorchestrator trident

# Expected output:
# NAME      AGE
# trident   2m

# Check detailed status
kubectl describe tridentorchestrator trident | grep -A 5 "Status:"

# Expected output:
# Status:                          Installed
# Version:                         v25.02.0

# Check all pods
kubectl get pods -n trident

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# trident-controller-7c9789fc59-qrxnc   6/6     Running   0          5m
# trident-node-linux-8nmdl              2/2     Running   0          5m
# trident-node-linux-f46xl              2/2     Running   0          5m
# trident-node-linux-fv2mx              2/2     Running   0          5m
# trident-operator-6fcd8c68b9-s46mj     1/1     Running   0          8m

# Verify CSI driver registration
kubectl get csidriver

# Expected output:
# NAME                    ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES        AGE
# csi.trident.netapp.io   true             false            false             <unset>         false               Persistent   5m
```

## Configuration Files

### Operator Configuration (deploy/operator.yaml)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trident-operator
  namespace: trident
spec:
  # ... other specs ...
  template:
    spec:
      containers:
        - name: trident-operator
          image: netapp/trident-operator:25.02.0  # NetApp official image
          command:
          - "/trident-operator"
          - "--debug"
```

### TridentOrchestrator Configuration (deploy/crds/tridentorchestrator_cr_k8s_1_29.yaml)
```yaml
apiVersion: trident.netapp.io/v1
kind: TridentOrchestrator
metadata:
  name: trident
spec:
  debug: true
  namespace: trident
  imagePullPolicy: IfNotPresent
  
  # NetApp official images for K8s 1.29
  tridentImage: "netapp/trident:25.02.0"
  autosupportImage: "netapp/trident-autosupport:25.02"
  
  # CSI sidecar images
  nodeDriverRegistrarImage: "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0"
  csiAttacherImage: "registry.k8s.io/sig-storage/csi-attacher:v4.7.0"
  csiProvisionerImage: "registry.k8s.io/sig-storage/csi-provisioner:v5.1.0"
  csiResizerImage: "registry.k8s.io/sig-storage/csi-resizer:v1.12.0"
  csiSnapshotterImage: "registry.k8s.io/sig-storage/csi-snapshotter:v8.2.0"
  
  # Optimized settings for K8s 1.29
  disableAuditLog: true
  silenceAutosupport: false
  enableForceDetach: false
```

## Key Success Factors

### ✅ What Works on K8s 1.29
- **NetApp Official Images**: `netapp/trident:25.02.0` and `netapp/trident-operator:25.02.0`
- **No Version Warnings**: Unlike K8s 1.33, no unsupported version warnings
- **Proper Binary Paths**: NetApp images have correct binary locations
- **CSI Sidecar Images**: Standard registry.k8s.io images work perfectly

### ❌ What Doesn't Work
- **Nirmata Images**: Require authentication (ghcr.io/nirmata/...)
- **Custom Images**: May have binary path issues
- **K8s 1.33**: Not officially supported by Trident 25.02.0

## Troubleshooting

### Common Issues and Solutions

1. **Image Pull Errors**
   ```bash
   # If using Nirmata images, you'll get 401 Unauthorized
   # Solution: Use NetApp official images
   ```

2. **Binary Path Errors**
   ```bash
   # Error: exec: "/trident_orchestrator": no such file or directory
   # Solution: Use NetApp official images (they have correct paths)
   ```

3. **Pod Startup Issues**
   ```bash
   # Check pod events
   kubectl describe pod <pod-name> -n trident
   
   # Check operator logs
   kubectl logs -n trident -l app=operator.trident.netapp.io
   ```

### Diagnostic Commands
```bash
# Check TridentOrchestrator events
kubectl get events -n trident --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -n trident -l app=controller.csi.trident.netapp.io

# Check node pod logs
kubectl logs -n trident -l app=node.csi.trident.netapp.io

# Verify CSI driver
kubectl get csidriver csi.trident.netapp.io -o yaml
```

## Next Steps After Installation

### 1. Configure Storage Backend
```bash
# Example: ONTAP NAS backend
kubectl apply -f sample-input/backends-samples/ontap-nas/backend-tbc-ontap-nas.yaml
```

### 2. Create Storage Classes
```bash
# Basic storage class
kubectl apply -f sample-input/storage-class-samples/storage-class-basic.yaml
```

### 3. Test with PVC
```bash
# Test PVC creation
kubectl apply -f sample-input/pvc-samples/pvc-basic.yaml
```

## Success Indicators

✅ **Complete Success:**
- TridentOrchestrator status: `Installed`
- All pods in `Running` state with correct ready counts
- CSI driver registered: `csi.trident.netapp.io`
- No crash loops or image pull errors
- No Kubernetes version warnings

## Important Notes

- **Kubernetes 1.29 Support**: ✅ Fully supported by Trident 25.02.0
- **Image Registry**: Use NetApp official images for best compatibility
- **Binary Paths**: NetApp images have correct binary locations
- **Testing**: This deployment was verified on Kind cluster with K8s 1.29.12

## Files Created for This Guide

- `deploy/crds/tridentorchestrator_cr_k8s_1_29.yaml` - Optimized configuration for K8s 1.29
- `TRIDENT_K8S_1_29_DEPLOYMENT_GUIDE.md` - This comprehensive guide

---

**Tested and Verified**: This deployment was successfully tested on a Kind cluster running Kubernetes 1.29.12, which matches the customer's Nirmata managed cluster environment. 