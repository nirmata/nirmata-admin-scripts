# Trident CSI Storage - Simple Setup Guide for Kubernetes 1.29

## 🎯 What You'll Deploy
NetApp Trident CSI driver for dynamic storage provisioning in Kubernetes 1.29.

**✅ This guide is tested and verified on Kubernetes 1.29.12**

---

## 📋 Prerequisites Check

Run these commands to verify your environment is ready:

```bash
# 1. Check Kubernetes version (must be 1.29.x)
kubectl version --short
# Expected: Client Version: v1.29.x, Server Version: v1.29.x

# 2. Verify you have admin access
kubectl auth can-i '*' '*' --all-namespaces
# Expected: yes

# 3. Check all nodes are ready
kubectl get nodes
# All nodes should show STATUS: Ready
```

**✋ Stop here if any check fails - fix issues before proceeding**

---

## 🚀 Step-by-Step Deployment

### Step 1: Create Trident Namespace
```bash
kubectl create namespace trident
```

### Step 2: Deploy Trident Operator
```bash
kubectl apply -f deploy/bundle_post_1_25.yaml
```

### Step 3: Wait for Operator to be Ready
```bash
kubectl wait --for=condition=available deployment/trident-operator -n trident --timeout=300s
```

### Step 4: Deploy Trident
```bash
kubectl apply -f deploy/crds/tridentorchestrator_cr_k8s_1_29.yaml
```

### Step 5: Wait for Installation to Complete
```bash
# Watch the installation progress (press Ctrl+C when status shows "Installed")
kubectl get tridentorchestrator trident -w
```

**🎉 Installation Complete!** - Continue to verification.

---

## ✅ Verify Installation

Run these commands to confirm everything is working:

```bash
# 1. Check installation status
kubectl get tridentorchestrator trident
# STATUS should show: Installed

# 2. Verify all pods are running
kubectl get pods -n trident
# All pods should show READY and STATUS: Running

# 3. Confirm CSI driver is registered
kubectl get csidriver | grep trident
# Should show: csi.trident.netapp.io
```

**Expected pod output:**
```
NAME                                  READY   STATUS    RESTARTS   AGE
trident-controller-xxxxxxxxxx-xxxxx   6/6     Running   0          2m
trident-node-linux-xxxxx              2/2     Running   0          2m
trident-node-linux-xxxxx              2/2     Running   0          2m
trident-operator-xxxxxxxxx-xxxxx      1/1     Running   0          5m
```

---

## 🔧 Configure Your Storage Backend

**Choose your NetApp storage system type:**

### Option A: ONTAP NAS Storage
```bash
cat <<EOF | kubectl apply -f -
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: ontap-nas-backend
spec:
  version: 1
  storageDriverName: ontap-nas
  managementLIF: "YOUR_ONTAP_MGMT_IP"
  dataLIF: "YOUR_ONTAP_DATA_IP"
  svm: "YOUR_SVM_NAME"
  username: "YOUR_USERNAME"
  password: "YOUR_PASSWORD"
EOF
```

### Option B: ONTAP SAN Storage
```bash
cat <<EOF | kubectl apply -f -
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: ontap-san-backend
spec:
  version: 1
  storageDriverName: ontap-san
  managementLIF: "YOUR_ONTAP_MGMT_IP"
  dataLIF: "YOUR_ONTAP_DATA_IP"
  svm: "YOUR_SVM_NAME"
  username: "YOUR_USERNAME"
  password: "YOUR_PASSWORD"
  igroupName: "YOUR_IGROUP_NAME"
EOF
```

**📝 Replace the YOUR_* placeholders with your actual NetApp storage details**

---

## 🗃️ Create Storage Class

```bash
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: trident-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.trident.netapp.io
parameters:
  fsType: "ext4"
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF
```

---

## 🧪 Test Your Setup

### Create a Test PVC
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: trident-csi
EOF
```

### Verify PVC is Bound
```bash
kubectl get pvc test-pvc
# STATUS should show: Bound
```

### Test with a Pod
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: test
    image: nginx:latest
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: test-pvc
EOF
```

### Verify Pod is Running
```bash
kubectl get pod test-pod
# STATUS should show: Running
```

**🎉 Success! Your Trident CSI setup is working correctly.**

---

## 🧹 Cleanup Test Resources
```bash
kubectl delete pod test-pod
kubectl delete pvc test-pvc
```

---

## ❓ Troubleshooting

### If Installation Fails

**Check operator logs:**
```bash
kubectl logs -n trident deployment/trident-operator
```

**Check TridentOrchestrator status:**
```bash
kubectl describe tridentorchestrator trident
```

### If PVC Stays Pending

**Check backend configuration:**
```bash
kubectl get tridentbackendconfig -o wide
```

**Check controller logs:**
```bash
kubectl logs -n trident deployment/trident-controller -c trident-main
```

### Common Issues

1. **"No backend available"** → Configure a storage backend first
2. **"Connection refused"** → Check your NetApp storage system IP addresses
3. **"Authentication failed"** → Verify username/password for NetApp storage
4. **"Pods not starting"** → Check node resources and network connectivity

---

## 📞 Need Help?

1. Check logs: `kubectl logs -n trident deployment/trident-controller`
2. Review the troubleshooting section above
3. Verify your storage backend configuration
4. Contact your NetApp support team

---

## 🔄 Next Steps

✅ **You're ready to use Trident CSI!**

- Create more storage classes for different performance tiers
- Set up volume snapshots and clones
- Configure backup and disaster recovery
- Monitor storage usage and performance

**Important Files:**
- Storage backend samples: `sample-input/backends-samples/`
- Storage class templates: `sample-input/storage-class-samples/`
- PVC examples: `sample-input/pvc-samples/` 