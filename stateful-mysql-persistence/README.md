# Stateful MySQL Persistence on Kubernetes

## What This Does

This implementation runs MySQL as a Kubernetes StatefulSet with stable network identities and dedicated persistent storage for every replica. Each pod maintains a deterministic ordinal identity and automatically reconnects to its original PersistentVolumeClaim after recreation or scaling operations. The configuration also demonstrates ordered scaling, rolling updates, service discovery, health validation, and retained storage during workload removal. This pattern is useful for stateful systems where application identity and durable data must survive container lifecycle events.

## Architecture

    Kubernetes Cluster
           |
           +-----------------------------+
           |                             |
           v                             v
    Headless Service              ClusterIP Service
     mysql-headless                 mysql-service
     clusterIP: None                   :3306
           |                             |
           +--------------+--------------+
                          |
                          v
                StatefulSet Controller
                   mysql-statefulset
                          |
        +-----------------+-----------------+
        |                 |                 |
        v                 v                 v
  +-------------+   +-------------+   +-------------+
  | mysql-0     |   | mysql-1     |   | mysql-2     |
  | Stable DNS  |   | Stable DNS  |   | Stable DNS  |
  | MySQL 3306  |   | MySQL 3306  |   | MySQL 3306  |
  +------+------+   +------+------+   +------+------+
         |                 |                 |
         v                 v                 v
  +-------------+   +-------------+   +-------------+
  | PVC mysql-0 |   | PVC mysql-1 |   | PVC mysql-2 |
  | RWO Storage |   | RWO Storage |   | RWO Storage |
  +------+------+   +------+------+   +------+------+
         |                 |                 |
         +-----------------+-----------------+
                          |
                          v
                 Dynamic StorageClass
                          |
                          v
                  PersistentVolumes

Each replica receives its own persistent volume. When a pod is deleted or recreated, its ordinal identity remains stable and the replacement pod reattaches to the original PVC.

## Prerequisites

- Linux environment
- Kubernetes cluster
- kubectl
- Valid kubeconfig context
- Dynamic StorageClass
- Container runtime available to Kubernetes
- Internet access for pulling container images
- Sufficient CPU and memory for multiple MySQL replicas

Recommended validation:

    kubectl cluster-info
    kubectl get nodes
    kubectl config current-context
    kubectl get storageclass

A working dynamic StorageClass must exist before deploying the StatefulSet.

For a lightweight single-node setup, K3s can provide Kubernetes with local dynamic storage:

    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable=traefik" sh -

    mkdir -p "$HOME/.kube"

    sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    chmod 600 "$HOME/.kube/config"

    export KUBECONFIG="$HOME/.kube/config"

    kubectl wait \
      --for=condition=Ready \
      node \
      --all \
      --timeout=180s

    kubectl get storageclass

## Setup & Installation

Create the namespace:

    kubectl create namespace statefulset-lab

Set it as the active namespace:

    kubectl config set-context \
      --current \
      --namespace=statefulset-lab

Verify the default StorageClass:

    kubectl get storageclass

Deploy the headless Service:

    kubectl apply -f mysql-headless-service.yaml

Deploy the StatefulSet:

    kubectl apply -f mysql-statefulset.yaml

Check rollout and pod readiness:

    kubectl get statefulset mysql-statefulset
    kubectl get pods -o wide
    kubectl get pvc -o wide

Deploy the regular MySQL Service:

    kubectl apply -f mysql-service.yaml

Validate services:

    kubectl get services -o wide

## How to Reproduce

### 1. Deploy the Stateful Workload

Apply the headless Service and StatefulSet:

    kubectl apply -f mysql-headless-service.yaml
    kubectl apply -f mysql-statefulset.yaml

The StatefulSet creates predictable pod identities:

    mysql-statefulset-0
    mysql-statefulset-1
    mysql-statefulset-2

Unlike a Deployment, these identities remain stable across pod recreation.

### 2. Verify Persistent Storage

Inspect PVCs:

    kubectl get pvc -o wide

Inspect PersistentVolumes:

    kubectl get pv -o wide

Each MySQL replica receives an independent PVC through the StatefulSet volume claim template.

### 3. Write Persistent Database Data

Create test data inside the first replica:

    kubectl exec mysql-statefulset-0 -- \
      mysql \
      -uroot \
      -prootpassword123 \
      -e "
    CREATE DATABASE IF NOT EXISTS testdb;
    USE testdb;

    CREATE TABLE IF NOT EXISTS test_table (
        id INT PRIMARY KEY,
        name VARCHAR(100)
    );

    INSERT INTO test_table (id, name)
    VALUES (1, 'StatefulSet Persistent Data')
    ON DUPLICATE KEY UPDATE
        name='StatefulSet Persistent Data';

    SELECT * FROM test_table;
    "

### 4. Test Persistence Across Pod Recreation

Capture the original pod identity:

    kubectl get pod mysql-statefulset-0 \
      -o jsonpath='{.metadata.uid}'

Delete the pod:

    kubectl delete pod mysql-statefulset-0

Wait for Kubernetes to recreate it:

    kubectl wait \
      --for=condition=Ready \
      pod/mysql-statefulset-0 \
      --timeout=300s

Verify that the database row still exists:

    kubectl exec mysql-statefulset-0 -- \
      mysql \
      -uroot \
      -prootpassword123 \
      -e "
    USE testdb;
    SELECT * FROM test_table;
    "

The replacement pod receives a new Kubernetes UID while retaining the same ordinal identity and original PVC.

### 5. Scale the StatefulSet

Scale from three replicas to five:

    kubectl scale statefulset mysql-statefulset \
      --replicas=5

Verify ordered replica creation:

    kubectl get pods -o wide
    kubectl get pvc -o wide

Scale down to two replicas:

    kubectl scale statefulset mysql-statefulset \
      --replicas=2

Verify that higher ordinal pods are removed first while their PVCs remain:

    kubectl get pods -o wide
    kubectl get pvc -o wide

Scale back to four replicas:

    kubectl scale statefulset mysql-statefulset \
      --replicas=4

Verify that recreated replicas reconnect to their existing claims:

    kubectl get pods -o wide
    kubectl get pvc -o wide

### 6. Perform a Rolling Update

Update MySQL resource limits:

    kubectl patch statefulset mysql-statefulset \
      --type='strategic' \
      -p='{
        "spec":{
          "template":{
            "spec":{
              "containers":[
                {
                  "name":"mysql",
                  "resources":{
                    "requests":{
                      "memory":"256Mi",
                      "cpu":"250m"
                    },
                    "limits":{
                      "memory":"1Gi",
                      "cpu":"1000m"
                    }
                  }
                }
              ]
            }
          }
        }
      }'

Monitor rollout:

    kubectl rollout status \
      statefulset/mysql-statefulset \
      --timeout=600s

### 7. Verify Stable DNS Identity

Run a temporary BusyBox pod:

    kubectl run dns-debug \
      --image=busybox:1.37 \
      --restart=Never \
      --command -- sleep 3600

Verify pod-specific DNS:

    kubectl exec dns-debug -- \
      nslookup \
      mysql-statefulset-0.mysql-headless.statefulset-lab.svc.cluster.local

    kubectl exec dns-debug -- \
      nslookup \
      mysql-statefulset-1.mysql-headless.statefulset-lab.svc.cluster.local

Each ordinal pod receives a stable DNS identity through the headless Service.

### 8. Verify Regular Service Access

Deploy the ClusterIP Service:

    kubectl apply -f mysql-service.yaml

Check the service:

    kubectl get service mysql-service -o wide

Verify TCP connectivity:

    kubectl exec dns-debug -- \
      nc -zvw5 \
      mysql-service.statefulset-lab.svc.cluster.local \
      3306

Inspect modern service backend discovery:

    kubectl get endpointslice \
      -l kubernetes.io/service-name=mysql-service \
      -o wide

### 9. Monitor and Troubleshoot

Inspect StatefulSet health:

    kubectl get statefulset mysql-statefulset -o wide
    kubectl describe statefulset mysql-statefulset

Inspect pods:

    kubectl get pods -o wide
    kubectl describe pod mysql-statefulset-0

Inspect MySQL logs:

    kubectl logs mysql-statefulset-0 --tail=50

Inspect PVCs and PVs:

    kubectl get pvc -o wide
    kubectl get pv -o wide

Verify the mounted database filesystem:

    kubectl exec mysql-statefulset-0 -- \
      df -h /var/lib/mysql

Inspect events:

    kubectl get events \
      --sort-by=.metadata.creationTimestamp

### 10. Demonstrate PVC Retention

Scale the StatefulSet to zero:

    kubectl scale statefulset mysql-statefulset \
      --replicas=0

Confirm pods terminate:

    kubectl get pods

Verify PVCs remain:

    kubectl get pvc -o wide

Delete the StatefulSet:

    kubectl delete statefulset mysql-statefulset

Verify PVCs still remain after controller deletion:

    kubectl get pvc -o wide

This demonstrates Kubernetes' conservative data-retention behavior for StatefulSet-managed storage.

## Tools Used

- Kubernetes
- StatefulSet
- kubectl
- K3s
- containerd
- MySQL 8.0
- PersistentVolume
- PersistentVolumeClaim
- StorageClass
- Local Path Provisioner
- Headless Service
- ClusterIP Service
- CoreDNS
- EndpointSlice
- BusyBox
- Linux
- YAML

## Key Skills Demonstrated

- Designing and operating Kubernetes stateful workloads
- Managing stable pod identities and deterministic replica naming
- Implementing per-replica persistent storage
- Validating data persistence across pod recreation
- Testing PVC retention during scale-down and controller deletion
- Performing controlled StatefulSet scaling
- Executing rolling workload updates
- Configuring headless Services for stable DNS discovery
- Exposing database workloads through Kubernetes Services
- Validating service connectivity and EndpointSlice backends
- Troubleshooting pods, logs, events, storage, and readiness conditions
- Detecting and replacing unsupported storage provisioning configuration
- Validating Kubernetes recovery and lifecycle behavior

## Real-World Use Case

This architecture applies to containerized stateful systems that require durable storage and predictable network identity. Examples include relational databases, distributed databases, message brokers, coordination systems, and clustered data platforms. In a production environment, the same StatefulSet principles would typically be combined with a managed CSI storage driver, encrypted persistent volumes, secrets management, automated backups, anti-affinity rules, topology-aware scheduling, disruption budgets, observability, and high-availability database replication.

## Lessons Learned

- StatefulSet pod identity is persistent at the logical level even when the underlying pod object is destroyed and recreated.
- PersistentVolumeClaims survive normal scale-down operations and StatefulSet deletion unless explicitly removed or governed by another retention policy.
- A headless Service enables deterministic pod-level DNS rather than load-balanced service discovery.
- Dynamic storage provisioning must be validated against the actual cluster instead of assuming a generic host-path provisioner exists.
- Stateful workloads require more deliberate lifecycle and storage management than stateless Deployments.

## Troubleshooting Log

### Kubernetes Client Present but No Cluster Context

The environment contained kubectl but no reachable Kubernetes API server or configured context.

Resolution:

- Installed a lightweight single-node K3s cluster.
- Configured the user kubeconfig.
- Verified node readiness before deploying workloads.

### Unsupported Host-Path Storage Provisioner

The original storage configuration referenced:

    kubernetes.io/host-path

This is not a generic dynamic provisioner available in modern Kubernetes environments.

Resolution:

- Detected the active cluster StorageClass dynamically.
- Used the K3s local-path provisioner.
- Verified PVC provisioning with a temporary persistent storage test before deploying MySQL.

### StatefulSet Pod Creation Race Condition

Waiting directly for:

    kubectl wait --for=condition=Ready pod/mysql-statefulset-0

failed because the StatefulSet controller had not created the pod object yet.

Resolution:

- Added an existence check before waiting for readiness.
- Waited for each ordinal pod sequentially.
- Preserved visibility into ordered StatefulSet creation.

### BusyBox DNS Lookup Returned Exit Code 1

Short-name lookup for:

    mysql-headless

resolved the correct Kubernetes service name but also attempted additional search-domain variants that returned NXDOMAIN. BusyBox therefore returned a non-zero status even though the valid Kubernetes DNS record resolved.

Resolution:

- Switched DNS verification to the fully qualified service name:

    mysql-headless.statefulset-lab.svc.cluster.local

- Used explicit FQDNs for stable pod DNS validation.

### Deprecated Kubernetes Endpoints API

Querying the legacy Endpoints resource produced a deprecation warning on the Kubernetes version used.

Resolution:

- Replaced Endpoints inspection with:

    kubectl get endpointslice

- Used the discovery.k8s.io EndpointSlice API for service backend verification.

### Data Persistence Validation

The first MySQL pod was deliberately deleted after inserting database data.

Validation confirmed:

- The replacement pod received a new Kubernetes UID.
- The pod retained its ordinal name.
- The original PVC was reattached.
- The previously inserted database row remained accessible.

### PVC Retention Validation

The StatefulSet was scaled to zero and subsequently deleted while PVCs were intentionally preserved.

Validation confirmed:

- Workload pods were removed.
- StatefulSet controller resources were removed.
- PersistentVolumeClaims remained available.
- Persistent data was not implicitly destroyed.
