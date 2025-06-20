# Simple Private Registry Guide

## 📦 Required Images

Copy these 8 images to your private registry:

```
ghcr.io/nirmata/trident-operator:25.02.0
ghcr.io/nirmata/trident:25.02.0
ghcr.io/nirmata/trident-autosupport:25.02
ghcr.io/nirmata/csi-node-driver-registrar:v2.13.0
ghcr.io/nirmata/csi-attacher:v4.7.0
ghcr.io/nirmata/csi-provisioner:v5.1.0
ghcr.io/nirmata/csi-resizer:v1.12.0
ghcr.io/nirmata/csi-snapshotter:v8.2.0
```

## 🔄 Copy Images to Your Registry

Replace `YOUR_REGISTRY` with your actual registry:

```bash
# Example: YOUR_REGISTRY = harbor.company.com/trident

docker pull ghcr.io/nirmata/trident-operator:25.02.0
docker tag ghcr.io/nirmata/trident-operator:25.02.0 YOUR_REGISTRY/trident-operator:25.02.0
docker push YOUR_REGISTRY/trident-operator:25.02.0

docker pull ghcr.io/nirmata/trident:25.02.0
docker tag ghcr.io/nirmata/trident:25.02.0 YOUR_REGISTRY/trident:25.02.0
docker push YOUR_REGISTRY/trident:25.02.0

docker pull ghcr.io/nirmata/trident-autosupport:25.02
docker tag ghcr.io/nirmata/trident-autosupport:25.02 YOUR_REGISTRY/trident-autosupport:25.02
docker push YOUR_REGISTRY/trident-autosupport:25.02

docker pull ghcr.io/nirmata/csi-node-driver-registrar:v2.13.0
docker tag ghcr.io/nirmata/csi-node-driver-registrar:v2.13.0 YOUR_REGISTRY/csi-node-driver-registrar:v2.13.0
docker push YOUR_REGISTRY/csi-node-driver-registrar:v2.13.0

docker pull ghcr.io/nirmata/csi-attacher:v4.7.0
docker tag ghcr.io/nirmata/csi-attacher:v4.7.0 YOUR_REGISTRY/csi-attacher:v4.7.0
docker push YOUR_REGISTRY/csi-attacher:v4.7.0

docker pull ghcr.io/nirmata/csi-provisioner:v5.1.0
docker tag ghcr.io/nirmata/csi-provisioner:v5.1.0 YOUR_REGISTRY/csi-provisioner:v5.1.0
docker push YOUR_REGISTRY/csi-provisioner:v5.1.0

docker pull ghcr.io/nirmata/csi-resizer:v1.12.0
docker tag ghcr.io/nirmata/csi-resizer:v1.12.0 YOUR_REGISTRY/csi-resizer:v1.12.0
docker push YOUR_REGISTRY/csi-resizer:v1.12.0

docker pull ghcr.io/nirmata/csi-snapshotter:v8.2.0
docker tag ghcr.io/nirmata/csi-snapshotter:v8.2.0 YOUR_REGISTRY/csi-snapshotter:v8.2.0
docker push YOUR_REGISTRY/csi-snapshotter:v8.2.0
```

## 📝 Update 2 Files

### 1. Update `deploy/bundle_post_1_25.yaml`

**Line 476:** Change:
```yaml
image: netapp/trident-operator:25.02.0
```
**To:**
```yaml
image: YOUR_REGISTRY/trident-operator:25.02.0
```

### 2. Update `deploy/crds/tridentorchestrator_cr_k8s_1_29.yaml`

**Lines 12-20:** Change:
```yaml
tridentImage: "netapp/trident:25.02.0"
autosupportImage: "netapp/trident-autosupport:25.02"
nodeDriverRegistrarImage: "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0"
csiAttacherImage: "registry.k8s.io/sig-storage/csi-attacher:v4.7.0"
csiProvisionerImage: "registry.k8s.io/sig-storage/csi-provisioner:v5.1.0"
csiResizerImage: "registry.k8s.io/sig-storage/csi-resizer:v1.12.0"
csiSnapshotterImage: "registry.k8s.io/sig-storage/csi-snapshotter:v8.2.0"
```
**To:**
```yaml
tridentImage: "YOUR_REGISTRY/trident:25.02.0"
autosupportImage: "YOUR_REGISTRY/trident-autosupport:25.02"
nodeDriverRegistrarImage: "YOUR_REGISTRY/csi-node-driver-registrar:v2.13.0"
csiAttacherImage: "YOUR_REGISTRY/csi-attacher:v4.7.0"
csiProvisionerImage: "YOUR_REGISTRY/csi-provisioner:v5.1.0"
csiResizerImage: "YOUR_REGISTRY/csi-resizer:v1.12.0"
csiSnapshotterImage: "YOUR_REGISTRY/csi-snapshotter:v8.2.0"
```

## 🚀 Deploy

```bash
kubectl create namespace trident
kubectl apply -f deploy/bundle_post_1_25.yaml
kubectl apply -f deploy/crds/tridentorchestrator_cr_k8s_1_29.yaml
```

## ✅ Done!

Your Trident deployment now uses only your private registry. 