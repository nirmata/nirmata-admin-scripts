# Kubernetes Image Migration - Example Outputs & Post-Migration Scenarios

This document shows real example outputs and post-migration scenarios for the Kubernetes Image Migration Tool.

## 🔍 Pre-Migration State

### Current Resources Before Migration
```bash
$ kubectl get deployments,statefulsets,daemonsets,pods -n test-migration-1 -o wide

NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS    IMAGES                                                                                             SELECTOR
deployment.apps/test-app-deployment   0/2     2            0           5m38s   app,sidecar   docker-repo.nibr.novartis.net/nirmata/pause:3.6,docker-repo.nibr.novartis.net/nirmata/nginx:1.21   app=test-app

NAME                                READY   AGE     CONTAINERS   IMAGES
statefulset.apps/test-statefulset   0/2     5m38s   main         docker-repo.nibr.novartis.net/nirmata/pause:3.6

NAME                                       READY   STATUS                  RESTARTS   AGE     IP           NODE                           NOMINATED NODE   READINESS GATES
pod/test-app-deployment-5d4d6bd99c-9gqch   0/2     Init:ImagePullBackOff   0          5m38s   10.244.1.2   jfrog-migration-test-worker    <none>           <none>
pod/test-app-deployment-5d4d6bd99c-tmh69   0/2     Init:ImagePullBackOff   0          5m38s   10.244.2.2   jfrog-migration-test-worker2   <none>           <none>
pod/test-pod-with-secret                   0/1     ImagePullBackOff        0          5m38s   10.244.1.4   jfrog-migration-test-worker    <none>           <none>
pod/test-statefulset-0                     0/1     ImagePullBackOff        0          5m38s   10.244.2.3   jfrog-migration-test-worker2   <none>           <none>
```

### Current Image Configuration
```bash
# Container Images
$ kubectl get deployment test-app-deployment -n test-migration-1 -o jsonpath='{.spec.template.spec.containers[*].image}'
docker-repo.nibr.novartis.net/nirmata/pause:3.6 docker-repo.nibr.novartis.net/nirmata/nginx:1.21

# Init Container Images
$ kubectl get deployment test-app-deployment -n test-migration-1 -o jsonpath='{.spec.template.spec.initContainers[*].image}'
docker-repo.nibr.novartis.net/nirmata/busybox:1.35
```

**Status**: All pods are in `ImagePullBackOff` state because the source registry images don't exist.

---

## 🧪 Dry-Run Migration Output

### Command
```bash
./k8s-image-migration.sh --dry-run \
  --source-registry docker-repo.nibr.novartis.net \
  --dest-registry ghcr.io/vikashkaushik01 \
  --namespace test-migration-1 \
  --output-plan pre-migration-plan.json
```

### Output
```
[INFO] Kubernetes Image Migration Tool
[INFO] Source Registry: docker-repo.nibr.novartis.net
[INFO] Destination Registry: ghcr.io/vikashkaushik01
[INFO] Namespace: test-migration-1
[INFO] Image Pull Secret: artifactory-secret
[INFO] Mode: DRY-RUN
[INFO] Scanning cluster for images matching source registry: docker-repo.nibr.novartis.net
[INFO] Scanning namespace: test-migration-1

================================================================================
                              MIGRATION PLAN
================================================================================
Source Registry: docker-repo.nibr.novartis.net
Destination Registry: ghcr.io/vikashkaushik01
Image Pull Secret: artifactory-secret
================================================================================

Namespace: test-migration-1
----------------------------------------
  Resource: deployment/test-app-deployment
    FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
    TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6

  Resource: deployment/test-app-deployment
    FROM: docker-repo.nibr.novartis.net/nirmata/nginx:1.21
    TO:   ghcr.io/vikashkaushik01/nirmata/nginx:1.21

  Resource: deployment/test-app-deployment
    FROM: docker-repo.nibr.novartis.net/nirmata/busybox:1.35
    TO:   ghcr.io/vikashkaushik01/nirmata/busybox:1.35

  Resource: statefulset/test-statefulset
    FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
    TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6

  Resource: pod/test-app-deployment-5d4d6bd99c-9gqch
    FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
    TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6

  Resource: pod/test-app-deployment-5d4d6bd99c-9gqch
    FROM: docker-repo.nibr.novartis.net/nirmata/nginx:1.21
    TO:   ghcr.io/vikashkaushik01/nirmata/nginx:1.21

  Resource: pod/test-app-deployment-5d4d6bd99c-9gqch
    FROM: docker-repo.nibr.novartis.net/nirmata/busybox:1.35
    TO:   ghcr.io/vikashkaushik01/nirmata/busybox:1.35

  Resource: pod/test-app-deployment-5d4d6bd99c-tmh69
    FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
    TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6

  Resource: pod/test-app-deployment-5d4d6bd99c-tmh69
    FROM: docker-repo.nibr.novartis.net/nirmata/nginx:1.21
    TO:   ghcr.io/vikashkaushik01/nirmata/nginx:1.21

  Resource: pod/test-app-deployment-5d4d6bd99c-tmh69
    FROM: docker-repo.nibr.novartis.net/nirmata/busybox:1.35
    TO:   ghcr.io/vikashkaushik01/nirmata/busybox:1.35

  Resource: pod/test-pod-with-secret
    FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
    TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6

  Resource: pod/test-statefulset-0
    FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
    TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6

================================================================================
Total images to migrate: 12
================================================================================
[SUCCESS] Migration plan saved to: pre-migration-plan.json

================================================================================
                    EXECUTING MIGRATION PLAN (DRY-RUN)
================================================================================
[INFO] [DRY-RUN] Migrating deployment/test-app-deployment in namespace test-migration-1
[INFO]   FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
[INFO]   TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6
[SUCCESS] Image updated successfully
[SUCCESS] imagePullSecret added successfully

[INFO] [DRY-RUN] Migrating deployment/test-app-deployment in namespace test-migration-1
[INFO]   FROM: docker-repo.nibr.novartis.net/nirmata/nginx:1.21
[INFO]   TO:   ghcr.io/vikashkaushik01/nirmata/nginx:1.21
[SUCCESS] Image updated successfully
[SUCCESS] imagePullSecret added successfully

[INFO] [DRY-RUN] Migrating deployment/test-app-deployment in namespace test-migration-1
[INFO]   FROM: docker-repo.nibr.novartis.net/nirmata/busybox:1.35
[INFO]   TO:   ghcr.io/vikashkaushik01/nirmata/busybox:1.35
[SUCCESS] Image updated successfully
[SUCCESS] imagePullSecret added successfully

[INFO] [DRY-RUN] Migrating statefulset/test-statefulset in namespace test-migration-1
[INFO]   FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
[INFO]   TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6
[SUCCESS] Image updated successfully
[SUCCESS] imagePullSecret added successfully

... (continues for all resources)

================================================================================
Migration plan completed: 12/12 successful
================================================================================
[SUCCESS] Migration completed successfully!
```

---

## ⚡ Actual Migration Execution

### Command
```bash
echo "y" | ./k8s-image-migration.sh \
  --source-registry docker-repo.nibr.novartis.net \
  --dest-registry ghcr.io/vikashkaushik01 \
  --namespace test-migration-1
```

### Output
```
[INFO] Kubernetes Image Migration Tool
[INFO] Source Registry: docker-repo.nibr.novartis.net
[INFO] Destination Registry: ghcr.io/vikashkaushik01
[INFO] Namespace: test-migration-1
[INFO] Image Pull Secret: artifactory-secret
[INFO] Scanning cluster for images matching source registry: docker-repo.nibr.novartis.net
[INFO] Scanning namespace: test-migration-1

================================================================================
                              MIGRATION PLAN
================================================================================
Source Registry: docker-repo.nibr.novartis.net
Destination Registry: ghcr.io/vikashkaushik01
Image Pull Secret: artifactory-secret
================================================================================

Namespace: test-migration-1
----------------------------------------
  Resource: deployment/test-app-deployment
    FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
    TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6

  Resource: deployment/test-app-deployment
    FROM: docker-repo.nibr.novartis.net/nirmata/nginx:1.21
    TO:   ghcr.io/vikashkaushik01/nirmata/nginx:1.21

  Resource: deployment/test-app-deployment
    FROM: docker-repo.nibr.novartis.net/nirmata/busybox:1.35
    TO:   ghcr.io/vikashkaushik01/nirmata/busybox:1.35

  Resource: statefulset/test-statefulset
    FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
    TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6

... (additional resources)

================================================================================
Total images to migrate: 12
================================================================================

================================================================================
                       EXECUTING MIGRATION PLAN
================================================================================
[INFO] Migrating deployment/test-app-deployment in namespace test-migration-1
[INFO]   FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
[INFO]   TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6
[SUCCESS] Image updated successfully
[SUCCESS] imagePullSecret added successfully

[INFO] Migrating deployment/test-app-deployment in namespace test-migration-1
[INFO]   FROM: docker-repo.nibr.novartis.net/nirmata/nginx:1.21
[INFO]   TO:   ghcr.io/vikashkaushik01/nirmata/nginx:1.21
[SUCCESS] Image updated successfully

[INFO] Migrating deployment/test-app-deployment in namespace test-migration-1
[INFO]   FROM: docker-repo.nibr.novartis.net/nirmata/busybox:1.35
[INFO]   TO:   ghcr.io/vikashkaushik01/nirmata/busybox:1.35
[SUCCESS] Image updated successfully

[INFO] Migrating statefulset/test-statefulset in namespace test-migration-1
[INFO]   FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
[INFO]   TO:   ghcr.io/vikashkaushik01/nirmata/pause:3.6
[SUCCESS] Image updated successfully
[SUCCESS] imagePullSecret added successfully

... (continues for all resources)

================================================================================
Migration execution completed: 12/12 successful
================================================================================
[SUCCESS] Migration completed successfully!
```

---

## 🎯 Post-Migration State

### Updated Resources After Migration
```bash
$ kubectl get deployments,statefulsets,daemonsets,pods -n test-migration-1 -o wide

NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS    IMAGES                                                                                 SELECTOR
deployment.apps/test-app-deployment   0/2     1            0           7m28s   app,sidecar   ghcr.io/vikashkaushik01/nirmata/pause:3.6,ghcr.io/vikashkaushik01/nirmata/nginx:1.21   app=test-app

NAME                                READY   AGE     CONTAINERS   IMAGES
statefulset.apps/test-statefulset   0/2     7m28s   main         ghcr.io/vikashkaushik01/nirmata/pause:3.6

NAME                                       READY   STATUS              RESTARTS   AGE     IP           NODE                           NOMINATED NODE   READINESS GATES
pod/test-app-deployment-795d44b64f-rm2mr   0/2     PodInitializing     0          9s      10.244.2.7   jfrog-migration-test-worker2   <none>           <none>
pod/test-app-deployment-86697f6785-l5r42   0/2     Init:ErrImagePull   0          10s     10.244.2.6   jfrog-migration-test-worker2   <none>           <none>
pod/test-app-deployment-98dd5596b-v6mx9    0/2     Init:ErrImagePull   0          10s     10.244.1.6   jfrog-migration-test-worker    <none>           <none>
pod/test-pod-with-secret                   0/1     ImagePullBackOff    0          7m28s   10.244.1.4   jfrog-migration-test-worker    <none>           <none>
pod/test-statefulset-0                     0/1     ImagePullBackOff    0          7m28s   10.244.2.3   jfrog-migration-test-worker2   <none>           <none>
```

### Updated Image Configuration
```bash
# Container Images - AFTER MIGRATION
$ kubectl get deployment test-app-deployment -n test-migration-1 -o jsonpath='{.spec.template.spec.containers[*].image}'
ghcr.io/vikashkaushik01/nirmata/pause:3.6 ghcr.io/vikashkaushik01/nirmata/nginx:1.21

# Init Container Images - AFTER MIGRATION
$ kubectl get deployment test-app-deployment -n test-migration-1 -o jsonpath='{.spec.template.spec.initContainers[*].image}'
ghcr.io/vikashkaushik01/nirmata/busybox:1.35
```

### ImagePullSecrets Status
```bash
# Deployment ImagePullSecrets
$ kubectl get deployment test-app-deployment -n test-migration-1 -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}'
artifactory-secret

# StatefulSet ImagePullSecrets
$ kubectl get statefulset test-statefulset -n test-migration-1 -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}'
artifactory-secret
```

---

## 🎮 Interactive Migration Example

### Command
```bash
./k8s-image-migration.sh --interactive --dry-run \
  --source-registry docker-repo.nibr.novartis.net \
  --dest-registry ghcr.io/vikashkaushik01 \
  --namespace test-migration-2
```

### Interactive Prompts & Responses
```
================================================================================
                    EXECUTING MIGRATION PLAN (DRY-RUN)
================================================================================

Migrate daemonset/test-daemonset in test-migration-2? (y/n/q): y
[INFO] [DRY-RUN] Migrating daemonset/test-daemonset in namespace test-migration-2
[SUCCESS] Image updated successfully
[SUCCESS] imagePullSecret added successfully

Migrate pod/test-daemonset-56r6b in test-migration-2? (y/n/q): n
[INFO] Skipping...

Migrate pod/test-daemonset-b54c4 in test-migration-2? (y/n/q): y
[INFO] [DRY-RUN] Migrating pod/test-daemonset-b54c4 in namespace test-migration-2
[SUCCESS] Image updated successfully
[SUCCESS] imagePullSecret added successfully

Migrate pod/test-pod-no-secret in test-migration-2? (y/n/q): q
[INFO] Migration cancelled by user.

================================================================================
Migration plan completed: 2/5 successful
================================================================================
```

---

## 📋 Migration Plan JSON Export

### Generated JSON Plan (`pre-migration-plan.json`)
```json
{
  "config": {
    "namespace": "test-migration-1",
    "source_registry": "docker-repo.nibr.novartis.net",
    "destination_registry": "ghcr.io/vikashkaushik01",
    "image_pull_secret": "artifactory-secret"
  },
  "images": [
    {
      "namespace": "test-migration-1",
      "resource_type": "deployment",
      "resource_name": "test-app-deployment",
      "source": "docker-repo.nibr.novartis.net/nirmata/pause:3.6",
      "destination": "ghcr.io/vikashkaushik01/nirmata/pause:3.6"
    },
    {
      "namespace": "test-migration-1",
      "resource_type": "deployment",
      "resource_name": "test-app-deployment",
      "source": "docker-repo.nibr.novartis.net/nirmata/nginx:1.21",
      "destination": "ghcr.io/vikashkaushik01/nirmata/nginx:1.21"
    },
    {
      "namespace": "test-migration-1",
      "resource_type": "deployment",
      "resource_name": "test-app-deployment",
      "source": "docker-repo.nibr.novartis.net/nirmata/busybox:1.35",
      "destination": "ghcr.io/vikashkaushik01/nirmata/busybox:1.35"
    },
    {
      "namespace": "test-migration-1",
      "resource_type": "statefulset",
      "resource_name": "test-statefulset",
      "source": "docker-repo.nibr.novartis.net/nirmata/pause:3.6",
      "destination": "ghcr.io/vikashkaushik01/nirmata/pause:3.6"
    }
  ]
}
```

---

## 🏭 Production Migration Scenarios

### Scenario 1: Novartis JFrog Migration (Your Use Case)

#### Command
```bash
./k8s-image-migration.sh --dry-run \
  --source-registry docker-repo.nibr.novartis.net \
  --dest-registry artifactory.f1.novartis.net/to-ddi-diu-zephyr-docker \
  --image-pull-secret artifactory-secret \
  --output-plan novartis-migration-plan.json
```

#### Expected Transformation
```
FROM: docker-repo.nibr.novartis.net/nirmata/pause:3.6
TO:   artifactory.f1.novartis.net/to-ddi-diu-zephyr-docker/nirmata/pause:3.6

FROM: docker-repo.nibr.novartis.net/app/backend:v1.2.3
TO:   artifactory.f1.novartis.net/to-ddi-diu-zephyr-docker/app/backend:v1.2.3

FROM: docker-repo.nibr.novartis.net/monitoring/prometheus:2.40.0
TO:   artifactory.f1.novartis.net/to-ddi-diu-zephyr-docker/monitoring/prometheus:2.40.0
```

### Scenario 2: Namespace-Specific Migration

#### Command
```bash
./k8s-image-migration.sh --interactive \
  --namespace production \
  --source-registry old-registry.company.com \
  --dest-registry new-registry.company.com \
  --image-pull-secret registry-credentials
```

#### Expected Output
```
================================================================================
                              MIGRATION PLAN
================================================================================
Source Registry: old-registry.company.com
Destination Registry: new-registry.company.com
Image Pull Secret: registry-credentials
================================================================================

Namespace: production
----------------------------------------
  Resource: deployment/web-frontend
    FROM: old-registry.company.com/frontend/web:v2.1.0
    TO:   new-registry.company.com/frontend/web:v2.1.0

  Resource: deployment/api-backend
    FROM: old-registry.company.com/backend/api:v1.5.2
    TO:   new-registry.company.com/backend/api:v1.5.2

  Resource: statefulset/database
    FROM: old-registry.company.com/db/postgresql:13.8
    TO:   new-registry.company.com/db/postgresql:13.8

================================================================================
Total images to migrate: 3
================================================================================
```

---

## ⚠️ Error Scenarios & Handling

### Scenario 1: Missing ImagePullSecret
```
[WARNING] imagePullSecret 'artifactory-secret' does not exist in namespace 'production'
[INFO] You may need to create the secret first:
[INFO] kubectl create secret docker-registry artifactory-secret \
[INFO]   --docker-server=<your-registry> \
[INFO]   --docker-username=<username> \
[INFO]   --docker-password=<password> \
[INFO]   -n production
```

### Scenario 2: Resource Not Found (Pods recreated during migration)
```
[INFO] Migrating pod/test-app-deployment-5d4d6bd99c-9gqch in namespace test-migration-1
Error from server (NotFound): pods "test-app-deployment-5d4d6bd99c-9gqch" not found
[SUCCESS] Image updated successfully
[ERROR] Failed to add imagePullSecret
[WARNING] Failed to add imagePullSecret, but image was updated
```

### Scenario 3: No Images Found
```
[WARNING] No images found matching the source registry pattern.

================================================================================
                              MIGRATION PLAN
================================================================================
Source Registry: nonexistent-registry.com
Destination Registry: new-registry.com
Image Pull Secret: artifactory-secret
================================================================================
[WARNING] No images found matching the source registry pattern.
```

---

## 📊 Migration Summary & Best Practices

### What Gets Updated
1. **Container Images**: All `containers[].image` fields
2. **Init Container Images**: All `initContainers[].image` fields
3. **ImagePullSecrets**: Added if missing, preserved if existing
4. **Resource Types**: Deployments, StatefulSets, DaemonSets, Pods, CronJobs, Jobs

### What Happens During Migration
1. **Scanning**: Identifies all resources with matching source registry
2. **Planning**: Creates detailed migration plan with before/after images
3. **Validation**: Checks for imagePullSecret existence
4. **Execution**: Updates images and adds secrets
5. **Reporting**: Provides success/failure counts and details

### Post-Migration Verification Commands
```bash
# Check updated images
kubectl get deployments -o wide --all-namespaces | grep new-registry

# Verify imagePullSecrets
kubectl get deployment <name> -n <namespace> -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}'

# Check pod status
kubectl get pods --all-namespaces | grep -E "(Running|ContainerCreating)"

# Verify specific resource
kubectl describe deployment <name> -n <namespace>
```

This comprehensive example shows exactly what to expect when running the migration tool in various scenarios, from dry-runs to actual migrations, with detailed before/after states and error handling examples.
