# Trident Offline Deployment Guide for Kubernetes 1.33

## Overview
This guide covers the manual deployment of Trident operator in offline mode for Kubernetes 1.33.1.

## Issues Identified

### 1. Kubernetes Version Support
- **Issue**: Trident 25.02.0 doesn't officially support Kubernetes 1.33.1
- **Impact**: Warning messages but should still work
- **Solution**: Proceed with deployment, expect warnings

### 2. Binary Path Issue
- **Issue**: Container tries to execute `/trident_orchestrator` but binary is at `/usr/local/bin/trident_orchestrator`
- **Impact**: CSI pods crash with "no such file or directory" error
- **Root Cause**: Different image builds have binary in different locations

### 3. Image Registry Configuration
- **Issue**: Need proper offline/private registry configuration
- **Impact**: Image pull failures in air-gapped environments

## Solutions

### Solution 1: Use Working Images (Recommended)

The Nirmata images have the correct binary paths:

```yaml
apiVersion: trident.netapp.io/v1
kind: TridentOrchestrator
metadata:
  name: trident
spec:
  debug: true
  namespace: trident
  imagePullPolicy: IfNotPresent
  
  # Use images with correct binary paths
  tridentImage: "ghcr.io/nirmata/trident:25.02.0"
  autosupportImage: "ghcr.io/nirmata/trident-autosupport:25.02"
  
  # CSI sidecar images
  nodeDriverRegistrarImage: "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0"
  csiAttacherImage: "registry.k8s.io/sig-storage/csi-attacher:v4.7.0"
  csiProvisionerImage: "registry.k8s.io/sig-storage/csi-provisioner:v5.1.0"
  csiResizerImage: "registry.k8s.io/sig-storage/csi-resizer:v1.12.0"
  csiSnapshotterImage: "registry.k8s.io/sig-storage/csi-snapshotter:v8.2.0"
  
  # Disable problematic features for K8s 1.33
  disableAuditLog: true
  silenceAutosupport: false
  enableForceDetach: false
```

### Solution 2: Private Registry Configuration

For air-gapped environments, mirror images to your private registry:

```yaml
apiVersion: trident.netapp.io/v1
kind: TridentOrchestrator
metadata:
  name: trident
spec:
  debug: true
  namespace: trident
  imagePullPolicy: IfNotPresent
  
  # Private registry images
  imageRegistry: "docker-repo.nibr.novartis.net/k8sgcr"
  tridentImage: "docker-repo.nibr.novartis.net/k8sgcr/trident:25.02.0"
  autosupportImage: "docker-repo.nibr.novartis.net/k8sgcr/trident-autosupport:25.02"
  
  # Image pull secrets
  imagePullSecrets:
  - nibr-registry-secret
  
  # Other settings...
```

## Required Images for Offline Deployment

### Core Trident Images
- `ghcr.io/nirmata/trident:25.02.0` (or `netapp/trident:25.02.0`)
- `ghcr.io/nirmata/trident-autosupport:25.02` (or `netapp/trident-autosupport:25.02`)
- `ghcr.io/nirmata/trident-operator:25.02.0`

### CSI Sidecar Images
- `registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0`
- `registry.k8s.io/sig-storage/csi-attacher:v4.7.0`
- `registry.k8s.io/sig-storage/csi-provisioner:v5.1.0`
- `registry.k8s.io/sig-storage/csi-resizer:v1.12.0`
- `registry.k8s.io/sig-storage/csi-snapshotter:v8.2.0`

## Step-by-Step Deployment

### Prerequisites
```bash
# Verify Kubernetes version
kubectl version

# Verify cluster admin privileges
kubectl auth can-i '*' '*' --all-namespaces

# Verify trident namespace exists
kubectl get namespace trident || kubectl create namespace trident
```

### Step 1: Deploy Trident Operator
```bash
# For Kubernetes 1.25+ (including 1.33)
kubectl apply -f deploy/bundle_post_1_25.yaml

# Verify operator is running
kubectl get deployment trident-operator -n trident
```

### Step 2: Create Image Pull Secret (if needed)
```bash
kubectl create secret docker-registry nibr-registry-secret \
  --docker-server=docker-repo.nibr.novartis.net \
  --docker-username=<username> \
  --docker-password=<password> \
  -n trident
```

### Step 3: Deploy TridentOrchestrator
```bash
# Apply the working configuration
kubectl apply -f deploy/crds/tridentorchestrator_cr_customimage_fix.yaml

# Monitor deployment
kubectl get tridentorchestrator trident -w
```

### Step 4: Verify Installation
```bash
# Check TridentOrchestrator status
kubectl describe tridentorchestrator trident

# Check pods
kubectl get pods -n trident

# Verify CSI functionality
kubectl get csidriver csi.trident.netapp.io
```

## Troubleshooting

### Common Issues

1. **Binary Path Error**
   ```
   exec: "/trident_orchestrator": stat /trident_orchestrator: no such file or directory
   ```
   **Solution**: Use Nirmata images or fix binary path

2. **Kubernetes Version Warning**
   ```
   Warning: Trident is running on an unsupported version of Kubernetes; v1.33.1
   ```
   **Solution**: This is expected, deployment should still work

3. **Image Pull Errors**
   ```
   Failed to pull image "registry.k8s.io/sig-storage/..."
   ```
   **Solution**: Ensure images are available in your environment

### Diagnostic Commands
```bash
# Check TridentOrchestrator status
kubectl get tridentorchestrator trident -o yaml

# Check operator logs
kubectl logs -n trident -l app=operator.trident.netapp.io

# Check failed pod details
kubectl describe pod <pod-name> -n trident

# Check events
kubectl get events -n trident --sort-by='.lastTimestamp'
```

## Success Indicators

✅ **Successful Deployment:**
- TridentOrchestrator status: `Installed`
- All pods in `Running` state
- No crash loops or image pull errors
- CSI driver registered

```bash
# Expected successful output
kubectl get pods -n trident
NAME                                       READY   STATUS    RESTARTS   AGE
trident-controller-7d466bf5c7-v4cpw        6/6     Running   0           5m
trident-node-linux-mr6zc                   2/2     Running   0           5m
trident-operator-766f7b8658-ldzsv          1/1     Running   0           10m
```

## Next Steps

After successful deployment:

1. **Configure Storage Backend**
   ```bash
   kubectl apply -f sample-input/backends-samples/ontap-nas/backend-tbc-ontap-nas.yaml
   ```

2. **Create Storage Classes**
   ```bash
   kubectl apply -f sample-input/storage-class-samples/storage-class-basic.yaml
   ```

3. **Test with PVC**
   ```bash
   kubectl apply -f sample-input/pvc-samples/pvc-basic.yaml
   ```

## Files Created

- `deploy/crds/tridentorchestrator_cr_customimage_fix.yaml` - Working configuration
- `deploy/crds/tridentorchestrator_cr_netapp_official.yaml` - NetApp official images
- `TRIDENT_OFFLINE_DEPLOYMENT_COMPLETE_GUIDE.md` - This guide

## Important Notes

- **Kubernetes 1.33 Support**: Not officially supported but should work
- **Binary Path Issue**: Critical - must use correct images
- **Air-gapped Deployment**: Requires all images in private registry
- **Testing**: Always test in non-production first 