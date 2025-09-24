## Sync Namespace Environment Associations with Nirmata

This script synchronizes Kubernetes namespace annotations with their corresponding environment associations in Nirmata. It fixes mismatched environment IDs and names, ensuring that namespaces in your cluster are properly linked to the correct environments in Nirmata.

## What it fixes:

- **Mismatched Environment IDs**: Updates namespace annotations when the environment ID doesn't match what's configured in Nirmata
- **Incorrect Environment Names**: Corrects environment name references in namespace annotations  
- **Orphaned Namespaces**: Associates namespaces that exist in the cluster but aren't linked to any Nirmata environment
- **Stale Associations**: Updates outdated environment references after migrations or configuration changes

## Usage: 

```sh
./sync-namespace-environment-associations.sh <NirmataURL> <cluster-name> <context-name>
```

**Example:**
```sh
./sync-namespace-environment-associations.sh https://pe420.nirmata.co testcluster kind-testcluster
```

## How it works:

1. **Fetches Current State**: Retrieves environment mappings from Nirmata API for the specified cluster
2. **Compares Associations**: Checks each namespace's current environment annotation against Nirmata's records
3. **Updates Mismatches**: Patches namespace annotations with correct environment IDs and names
4. **Handles Orphans**: Creates environment associations for namespaces missing from Nirmata

## Sample Output:

```sh

 ./fix-environment-names.sh https://pe420.nirmata.co testcluster kind-testcluster

Switched to context "kind-testcluster".

Enter the Nirmata API token:

Fetching environment details from Nirmata...
Environment data received:
[
  {
    "id": "44cbbdcd-3b80-4165-a074-340f8fc4f9d8",
    "name": "default-duktest",
    "namespace": "default"
  },
  {
    "id": "22c37c43-cd5b-4867-9499-7f2b3b45cee8",
    "name": "local-path-storage-duktest",
    "namespace": "local-path-storage"
  },
  {
    "id": "5f5cb880-4a6e-458e-925b-e027557f7c9e",
    "name": "kube-node-lease-duktest",
    "namespace": "kube-node-lease"
  },
  {
    "id": "ee3f2251-1716-4528-9c47-a7ce892f18e1",
    "name": "kube-system-duktest",
    "namespace": "kube-system"
  },
  {
    "id": "e97bdafd-4245-47ad-8bad-b4680cbd3b70",
    "name": "nirmata-duktest",
    "namespace": "nirmata"
  },
  {
    "id": "98fb8679-4d2d-4ad9-8168-f07b21469ed0",
    "name": "kube-public-duktest",
    "namespace": "kube-public"
  },
  {
    "id": "9ef3dea2-8c51-4e9b-a95b-3b179b2bc754",
    "name": "mytest",
    "namespace": "mytest"
  }
]
JSON is valid
default
local-path-storage
kube-node-lease
kube-system
nirmata
kube-public
mytest

Processing namespace: default
Namespace default already has correct environment ID: 44cbbdcd-3b80-4165-a074-340f8fc4f9d8

Processing namespace: local-path-storage
Namespace local-path-storage already has correct environment ID: 22c37c43-cd5b-4867-9499-7f2b3b45cee8

Processing namespace: kube-node-lease
Namespace kube-node-lease already has correct environment ID: 5f5cb880-4a6e-458e-925b-e027557f7c9e

Processing namespace: kube-system
Namespace kube-system already has correct environment ID: ee3f2251-1716-4528-9c47-a7ce892f18e1

Processing namespace: nirmata
Namespace nirmata already has correct environment ID: e97bdafd-4245-47ad-8bad-b4680cbd3b70

Processing namespace: kube-public
Namespace kube-public already has correct environment ID: 98fb8679-4d2d-4ad9-8168-f07b21469ed0

Processing namespace: mytest
Current environment ID: 9ef3dea2-8c51-4e9b-a95b-3b179b2bc75
New environment ID: 9ef3dea2-8c51-4e9b-a95b-3b179b2bc754
Environment name: mytest
namespace/mytest patched
Successfully updated annotations for namespace: mytest

```
