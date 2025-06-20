# Trident CSI - NetApp Storage Provisioner for Kubernetes

[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-blue.svg)](https://kubernetes.io/)
[![Trident](https://img.shields.io/badge/Trident-25.02.0-orange.svg)](https://github.com/NetApp/trident)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

## 📋 Overview

This repository contains everything you need to deploy **NetApp Trident CSI** (Container Storage Interface) driver on Kubernetes clusters. Trident is a dynamic storage provisioner that enables persistent storage for containerized applications using NetApp storage systems.

### ✅ What's Included

- **Complete Installation Guide** for Kubernetes 1.29
- **Pre-configured Deployment Files** for various K8s versions
- **Sample Configuration Files** for different NetApp storage backends
- **Storage Class Templates** for common use cases
- **Troubleshooting Documentation** and diagnostic tools
- **Offline/Air-gapped Deployment** support

---

## 🚀 Quick Start

### Prerequisites
- Kubernetes 1.21+ (tested on 1.29.12)
- Cluster admin privileges
- NetApp storage system (ONTAP, Element, Cloud Volumes, etc.)

### One-Command Installation
```bash
# Clone the repository
git clone https://github.com/vikashkaushik01/trident-csi.git
cd trident-csi

# Install Trident on Kubernetes 1.29
kubectl create namespace trident
kubectl apply -f deploy/bundle_post_1_25.yaml
kubectl apply -f deploy/crds/tridentorchestrator_cr_k8s_1_29.yaml

# Verify installation
kubectl get pods -n trident
```

---

## 📚 Documentation

### 📖 Installation Guides

| Guide | Description | Kubernetes Version |
|-------|-------------|-------------------|
| **[Customer Setup Guide](CUSTOMER_TRIDENT_K8S_1_29_SETUP_GUIDE.md)** | 🌟 **Complete customer-ready guide** | 1.29.x |
| [K8s 1.29 Deployment](TRIDENT_K8S_1_29_DEPLOYMENT_GUIDE.md) | Technical deployment guide | 1.29.x |
| [Offline Deployment](TRIDENT_OFFLINE_DEPLOYMENT_COMPLETE_GUIDE.md) | Air-gapped environment setup | 1.33.x |

### 🔧 Configuration Files

#### Deployment Files
- `deploy/bundle_post_1_25.yaml` - Complete bundle for K8s 1.25+
- `deploy/operator.yaml` - Trident operator deployment
- `deploy/crds/` - Custom Resource Definitions and examples

#### TridentOrchestrator Configurations
- `tridentorchestrator_cr_k8s_1_29.yaml` - Optimized for K8s 1.29 ✅
- `tridentorchestrator_cr_default.yaml` - Default configuration
- `tridentorchestrator_cr_customimage.yaml` - Custom image configuration
- `tridentorchestrator_cr_imagepullsecrets.yaml` - Private registry setup

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │   Application   │    │   Application   │                 │
│  │     Pods        │    │     Pods        │                 │
│  └─────────────────┘    └─────────────────┘                 │
│           │                       │                         │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Persistent Volumes (PV)                   │ │
│  └─────────────────────────────────────────────────────────┘ │
│           │                       │                         │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │               Trident CSI Driver                       │ │
│  │  ┌─────────────┐              ┌──────────────────────┐  │ │
│  │  │ Controller  │              │     Node Pods        │  │ │
│  │  │    Pods     │              │   (DaemonSet)        │  │ │
│  │  └─────────────┘              └──────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                NetApp Storage Systems                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │    ONTAP    │  │   Element   │  │   Cloud Volumes     │  │
│  │   (NAS/SAN) │  │ (SolidFire) │  │  (AWS/Azure/GCP)    │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Repository Structure

```
trident-csi/
├── 📚 README.md                                    # This file
├── 📖 CUSTOMER_TRIDENT_K8S_1_29_SETUP_GUIDE.md    # Complete customer guide
├── 📄 TRIDENT_K8S_1_29_DEPLOYMENT_GUIDE.md        # Technical deployment guide
├── 📄 TRIDENT_OFFLINE_DEPLOYMENT_COMPLETE_GUIDE.md # Offline deployment
├── 🔧 Download tridentctl from NetApp releases     # Trident CLI tool (see below)
├── 
├── 📁 deploy/                                      # Deployment files
│   ├── bundle_post_1_25.yaml                      # Complete K8s 1.25+ bundle
│   ├── operator.yaml                              # Trident operator
│   ├── namespace.yaml                             # Trident namespace
│   ├── serviceaccount.yaml                        # Service account
│   └── crds/                                      # Custom Resource Definitions
│       ├── tridentorchestrator_cr_k8s_1_29.yaml  # K8s 1.29 optimized ⭐
│       ├── tridentorchestrator_cr_default.yaml    # Default configuration
│       └── trident.netapp.io_*.yaml               # CRD definitions
│
├── 📁 sample-input/                               # Configuration samples
│   ├── backends-samples/                         # Storage backend configs
│   │   ├── ontap-nas/                            # ONTAP NAS examples
│   │   ├── ontap-san/                            # ONTAP SAN examples
│   │   ├── solidfire/                            # Element/SolidFire
│   │   └── azure-netapp-files/                   # Azure NetApp Files
│   ├── storage-class-samples/                    # Storage class templates
│   ├── pvc-samples/                              # PVC examples
│   └── snapshot-samples/                         # Volume snapshot examples
│
├── 📁 extras/                                     # Additional tools
│   └── (binaries not included - download from NetApp releases)
│
├── 📁 extras/                                     # Additional utilities
│   └── (Optional tools and binaries)
│
└── 🔧 kind-cluster-k8s-1.29.yaml                 # Kind cluster for testing
```

---

## ⚡ Supported Kubernetes Versions

| Kubernetes Version | Trident Version | Status | Guide |
|-------------------|-----------------|---------|-------|
| 1.29.x | 25.02.0 | ✅ **Recommended** | [Setup Guide](CUSTOMER_TRIDENT_K8S_1_29_SETUP_GUIDE.md) |
| 1.28.x | 25.02.0 | ✅ Supported | [Deployment Guide](TRIDENT_K8S_1_29_DEPLOYMENT_GUIDE.md) |
| 1.27.x | 25.02.0 | ✅ Supported | Use default configuration |
| 1.26.x | 25.02.0 | ✅ Supported | Use default configuration |
| 1.25.x | 25.02.0 | ✅ Supported | Use post_1_25 bundle |
| 1.33.x | 25.02.0 | ⚠️ Unofficial | [Offline Guide](TRIDENT_OFFLINE_DEPLOYMENT_COMPLETE_GUIDE.md) |

---

## 🔧 Storage Backends Supported

### NetApp ONTAP
- **ONTAP NAS** - NFS/SMB file shares
- **ONTAP SAN** - iSCSI/FC block storage
- **ONTAP NAS Economy** - Qtree-based volumes
- **ONTAP NAS FlexGroup** - Scale-out NAS volumes
- **ONTAP SAN Economy** - LUN-based storage

### NetApp Element (SolidFire)
- **Element** - High-performance block storage
- **Element** with virtual pools

### Cloud Storage
- **Azure NetApp Files** - Fully managed NFS/SMB
- **Google Cloud NetApp Volumes** - GCP managed storage
- **AWS FSx for NetApp ONTAP** - AWS managed ONTAP

---

## 🚀 Quick Examples

### Create Storage Backend
```yaml
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-ontap-nas
spec:
  version: 1
  storageDriverName: ontap-nas
  managementLIF: "10.0.0.1"
  dataLIF: "10.0.0.2"
  svm: "trident_svm"
  username: "admin"
  password: "password"
```

### Create Storage Class
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ontap-gold
provisioner: csi.trident.netapp.io
parameters:
  backendType: "ontap-nas"
  fsType: "ext4"
allowVolumeExpansion: true
```

### Create Persistent Volume Claim
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: ontap-gold
```

---

## 🛠 Tools and Utilities

### tridentctl CLI

**Download tridentctl binary:**
```bash
# Download from NetApp GitHub releases
wget https://github.com/NetApp/trident/releases/download/v25.02.0/trident-installer-25.02.0.tar.gz
tar -xf trident-installer-25.02.0.tar.gz
chmod +x trident-installer/tridentctl

# Basic commands
./tridentctl version
./tridentctl get backends -n trident
./tridentctl get volumes -n trident
./tridentctl logs -n trident
```

### Diagnostic Commands
```bash
# Check Trident status
kubectl get tridentorchestrator trident

# View pods
kubectl get pods -n trident

# Check CSI driver
kubectl get csidriver csi.trident.netapp.io

# View storage classes
kubectl get storageclass
```

---

## 🚨 Troubleshooting

### Common Issues

#### 1. Pod CrashLoopBackOff
```bash
# Check pod logs
kubectl logs -n trident <pod-name>

# Check pod events
kubectl describe pod -n trident <pod-name>
```

#### 2. Image Pull Errors
```bash
# Verify image availability
kubectl describe pod -n trident <pod-name>

# For private registries, create image pull secret
kubectl create secret docker-registry regcred \
  --docker-server=<registry> \
  --docker-username=<username> \
  --docker-password=<password> \
  -n trident
```

#### 3. Backend Connection Issues
```bash
# Check backend status
kubectl get tbc -n trident

# View backend logs
kubectl logs -n trident -l app=controller.csi.trident.netapp.io
```

### Getting Help
- 📖 [NetApp Trident Documentation](https://docs.netapp.com/us-en/trident/)
- 💬 [NetApp Community Forums](https://community.netapp.com/)
- 🐛 [GitHub Issues](https://github.com/NetApp/trident/issues)
- 📧 [Support Cases](https://mysupport.netapp.com/)

---

## 🤝 Contributing

We welcome contributions! Please read our contributing guidelines and submit pull requests.

### Development Setup
```bash
# Clone repository
git clone https://github.com/vikashkaushik01/trident-csi.git
cd trident-csi

# Test with Kind cluster
kind create cluster --config kind-cluster-k8s-1.29.yaml

# Deploy Trident
kubectl apply -f deploy/bundle_post_1_25.yaml
kubectl apply -f deploy/crds/tridentorchestrator_cr_k8s_1_29.yaml
```

---

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---

## 🏷 Tags

`kubernetes` `storage` `csi` `netapp` `trident` `persistent-volumes` `ontap` `solidfire` `cloud-volumes` `dynamic-provisioning`

---

**⭐ If this repository helped you, please give it a star!**

---

## 📞 Support

For commercial support and enterprise features, contact NetApp:
- 🌐 Website: [netapp.com](https://netapp.com)
- 📧 Email: [info@netapp.com](mailto:info@netapp.com)
- 📞 Phone: 1-877-263-8277

---

*Last updated: December 2024* 