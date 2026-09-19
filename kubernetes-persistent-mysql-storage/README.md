# Kubernetes Persistent Storage for MySQL

## What This Does

This implementation provisions durable storage for a MySQL workload running on Kubernetes using StorageClasses, PersistentVolumes, and PersistentVolumeClaims. It demonstrates explicitly bound storage alongside dynamically provisioned volumes while validating that database state survives pod replacement and full workload scale-down. The configuration also includes logical database backup, application-aware health validation, modern service endpoint inspection, and practical storage troubleshooting. The result is a reproducible foundation for operating stateful workloads reliably on Kubernetes.

## Architecture

~~text
                         Kubernetes Cluster
                                |
                +---------------+---------------+
                |                               |
                v                               v
        +----------------+             +-------------------+
        | StorageClass   |             | mysql-service     |
        | fast-storage   |             | ClusterIP :3306   |
        | local-path     |             +---------+---------+
        +-------+--------+                       |
                |                                v
                |                      +-------------------+
                |                      | MySQL Deployment  |
                |                      | mysql:8.0         |
                |                      | 1 replica         |
                |                      +---------+---------+
                |                                |
                v                                v
        +----------------+             +-------------------+
        | mysql-pv       |<------------| mysql-pvc         |
        | 5Gi / RWO      |             | 5Gi / RWO        |
        | Retain         |             +-------------------+
        +-------+--------+
                |
                v
        /var/lib/mysql-data
                |
                v
        Persistent MySQL Data


        Dynamic Provisioning Path
        -------------------------

        fast-storage
             |
             v
        dynamic-pvc
             |
             v
        Dynamically Provisioned PV
             |
             v
        dynamic-storage-consumer
             |
             v
        /data/proof.txt
~~

## Prerequisites

- Ubuntu Linux
- sudo privileges
- Kubernetes cluster
- kubectl configured with active cluster access
- Git
- Internet access for container images
- Approximately 2 CPU cores
- Approximately 4 GiB memory
- Sufficient local disk capacity

The validated environment used a single-node K3s cluster with the Rancher local-path provisioner.

## Setup & Installation

Install the required base packages:

~~bash
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates
~~

Install a lightweight K3s cluster:

~~bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server --disable=traefik" \
  sh -
~~

Configure kubectl access:

~~bash
mkdir -p "$HOME/.kube"

sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$USER:$USER" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
~~

Verify cluster connectivity:

~~bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get storageclass -o wide
~~

## How to Reproduce

### 1. Create the Custom StorageClass

Apply the custom storage configuration:

~~bash
kubectl apply -f custom-storageclass.yaml
~~

Verify it:

~~bash
kubectl get storageclass fast-storage -o wide
kubectl describe storageclass fast-storage
~~

The StorageClass uses the working local-path provisioner and `WaitForFirstConsumer` volume binding.

### 2. Prepare Persistent MySQL Storage

Create the host storage location:

~~bash
sudo mkdir -p /var/lib/mysql-data
sudo chmod 0777 /var/lib/mysql-data
~~

Create the PersistentVolume:

~~bash
kubectl apply -f mysql-pv.yaml
~~

Create the PersistentVolumeClaim:

~~bash
kubectl apply -f mysql-pvc.yaml
~~

Verify both resources:

~~bash
kubectl get pv mysql-pv -o wide
kubectl get pvc mysql-pvc -o wide
~~

The claim requests 5 GiB of `ReadWriteOnce` capacity and binds to the MySQL volume using matching labels.

### 3. Create MySQL Credentials

Credential material is intentionally excluded from source control.

Create the Kubernetes Secret directly:

~~bash
kubectl create secret generic mysql-secret \
  --from-literal=mysql-root-password='MySecurePassword123' \
  --from-literal=mysql-database='testdb' \
  --from-literal=mysql-user='testuser' \
  --from-literal=mysql-password='TestUserPassword123'
~~

For production environments, use a dedicated secrets-management system rather than plaintext credentials.

### 4. Deploy MySQL

Deploy the database workload:

~~bash
kubectl apply -f mysql-deployment.yaml
~~

Deploy the internal service:

~~bash
kubectl apply -f mysql-service.yaml
~~

Wait for MySQL to become ready:

~~bash
kubectl wait \
  --for=condition=Ready \
  pod \
  -l app=mysql \
  --timeout=300s
~~

Verify the running resources:

~~bash
kubectl get deployment mysql-deployment
kubectl get pods -l app=mysql -o wide
kubectl get service mysql-service -o wide
kubectl get pvc mysql-pvc -o wide
kubectl get pv mysql-pv -o wide
~~

The workload mounts persistent storage at:

~~text
/var/lib/mysql
~~

The Deployment uses a `Recreate` strategy so multiple MySQL instances do not compete for the same `ReadWriteOnce` volume during replacement.

### 5. Verify MySQL Health

Get the active MySQL pod:

~~bash
MYSQL_POD="$(kubectl get pods \
  -l app=mysql \
  -o jsonpath='{.items[0].metadata.name}')"
~~

Verify the database over TCP:

~~bash
kubectl exec "$MYSQL_POD" -- \
  mysqladmin \
  --protocol=TCP \
  -h 127.0.0.1 \
  -P 3306 \
  -uroot \
  -pMySecurePassword123 \
  ping
~~

Expected result:

~~text
mysqld is alive
~~

### 6. Create Persistence Test Data

Insert a clean three-record baseline:

~~bash
kubectl exec "$MYSQL_POD" -- \
  mysql \
  --protocol=TCP \
  -h 127.0.0.1 \
  -uroot \
  -pMySecurePassword123 \
  -e "
CREATE DATABASE IF NOT EXISTS testdb;

USE testdb;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

TRUNCATE TABLE users;

INSERT INTO users (name, email) VALUES
    ('John Doe', 'john@example.com'),
    ('Jane Smith', 'jane@example.com'),
    ('Bob Johnson', 'bob@example.com');

SELECT * FROM users;
"
~~

Verify the row count:

~~bash
kubectl exec "$MYSQL_POD" -- \
  mysql \
  --protocol=TCP \
  -h 127.0.0.1 \
  -N -s \
  -uroot \
  -pMySecurePassword123 \
  -e 'SELECT COUNT(*) FROM testdb.users;'
~~

Expected result:

~~text
3
~~

### 7. Verify Persistence Across Pod Replacement

Delete the current database pod:

~~bash
kubectl delete pod "$MYSQL_POD"
~~

Wait for Kubernetes to create and initialize its replacement:

~~bash
kubectl wait \
  --for=condition=Ready \
  pod \
  -l app=mysql \
  --timeout=300s
~~

Get the replacement pod:

~~bash
NEW_MYSQL_POD="$(kubectl get pods \
  -l app=mysql \
  -o jsonpath='{.items[0].metadata.name}')"
~~

Verify the original records:

~~bash
kubectl exec "$NEW_MYSQL_POD" -- \
  mysql \
  --protocol=TCP \
  -h 127.0.0.1 \
  -uroot \
  -pMySecurePassword123 \
  -e "
USE testdb;
SELECT * FROM users;
SELECT COUNT(*) AS total_users FROM users;
"
~~

The same three records should remain available after pod replacement.

### 8. Verify Persistence Across Complete Scale-Down

Scale the workload to zero:

~~bash
kubectl scale deployment/mysql-deployment --replicas=0
~~

Confirm that no MySQL pod remains:

~~bash
kubectl get pods -l app=mysql
~~

Verify that persistent storage remains bound:

~~bash
kubectl get pvc mysql-pvc -o wide
kubectl get pv mysql-pv -o wide
~~

Scale MySQL back to one replica:

~~bash
kubectl scale deployment/mysql-deployment --replicas=1
~~

Wait for readiness:

~~bash
kubectl wait \
  --for=condition=Ready \
  pod \
  -l app=mysql \
  --timeout=300s
~~

Get the new pod:

~~bash
SCALED_MYSQL_POD="$(kubectl get pods \
  -l app=mysql \
  -o jsonpath='{.items[0].metadata.name}')"
~~

Verify that the original records still exist:

~~bash
kubectl exec "$SCALED_MYSQL_POD" -- \
  mysql \
  --protocol=TCP \
  -h 127.0.0.1 \
  -uroot \
  -pMySecurePassword123 \
  -e "
USE testdb;
SELECT * FROM users;
SELECT COUNT(*) AS total_users FROM users;
"
~~

### 9. Inspect Storage Usage

Inspect Kubernetes storage objects:

~~bash
kubectl get pv,pvc -o wide
kubectl describe pv mysql-pv
kubectl describe pvc mysql-pvc
~~

Inspect host-level database storage:

~~bash
sudo du -sh /var/lib/mysql-data
sudo ls -lah /var/lib/mysql-data
~~

Inspect filesystem capacity:

~~bash
df -h /var/lib/mysql-data
~~

### 10. Create a Logical MySQL Backup

Create the backup location:

~~bash
sudo mkdir -p /backup/mysql
sudo chmod 0755 /backup/mysql
~~

Get the active database pod:

~~bash
MYSQL_POD="$(kubectl get pods \
  -l app=mysql \
  -o jsonpath='{.items[0].metadata.name}')"
~~

Create the database dump:

~~bash
kubectl exec "$MYSQL_POD" -- \
  mysqldump \
  --protocol=TCP \
  -h 127.0.0.1 \
  -uroot \
  -pMySecurePassword123 \
  --all-databases \
  > /tmp/mysql-backup.sql
~~

Store a timestamped copy:

~~bash
sudo cp /tmp/mysql-backup.sql \
  /backup/mysql/mysql-backup-$(date +%Y%m%d-%H%M%S).sql
~~

Verify backup creation:

~~bash
sudo ls -lh /backup/mysql/
~~

Database dumps are intentionally excluded from version control.

### 11. Validate Dynamic Volume Provisioning

Create a new claim without manually creating a corresponding PersistentVolume:

~~bash
kubectl apply -f dynamic-pvc.yaml
~~

Because the StorageClass uses `WaitForFirstConsumer`, create the storage consumer:

~~bash
kubectl apply -f dynamic-storage-consumer.yaml
~~

Watch the claim transition to `Bound`:

~~bash
kubectl get pvc dynamic-pvc -w
~~

Get the automatically provisioned volume:

~~bash
DYNAMIC_PV="$(kubectl get pvc dynamic-pvc \
  -o jsonpath='{.spec.volumeName}')"

echo "$DYNAMIC_PV"
~~

Inspect it:

~~bash
kubectl get pv "$DYNAMIC_PV" -o wide
kubectl describe pv "$DYNAMIC_PV"
~~

Verify that the consuming workload can write to the dynamically provisioned volume:

~~bash
kubectl exec dynamic-storage-consumer -- \
  cat /data/proof.txt
~~

Expected output:

~~text
dynamic-storage-provisioning-success
~~

### 12. Verify Modern Service Endpoint Discovery

Inspect the MySQL service backend using EndpointSlice:

~~bash
kubectl get endpointslice \
  -l kubernetes.io/service-name=mysql-service \
  -o wide
~~

## Tools Used

- Kubernetes
- K3s
- kubectl
- Rancher Local Path Provisioner
- StorageClass
- PersistentVolume
- PersistentVolumeClaim
- MySQL 8.0
- Kubernetes Secret
- Kubernetes Deployment
- Kubernetes Service
- EndpointSlice
- BusyBox
- mysqldump
- Linux filesystem utilities
- Git

## Key Skills Demonstrated

- Kubernetes persistent storage architecture
- StorageClass configuration and provisioner selection
- PersistentVolume and PersistentVolumeClaim lifecycle management
- Static volume binding
- Dynamic volume provisioning
- Stateful MySQL deployment
- Durable database storage
- Persistence validation across pod replacement
- Persistence validation across workload scale-down and recovery
- Kubernetes health probing
- TCP-based database validation
- Kubernetes service discovery
- EndpointSlice inspection
- Logical database backup
- Host-level storage inspection
- Storage troubleshooting
- Failure-safe remote shell execution

## Real-World Use Case

This architecture applies to organizations operating stateful services such as relational databases, internal data platforms, monitoring systems, artifact repositories, build systems, and other workloads that cannot lose state when containers are recreated. PersistentVolumes decouple application data from pod lifecycle, while PersistentVolumeClaims provide workloads with a stable storage contract. Dynamic provisioning further reduces operational overhead by allowing Kubernetes to create backing volumes automatically when applications request storage.

## Lessons Learned

- Container lifecycle and data lifecycle must be designed independently for stateful workloads.
- A StorageClass name alone does not provide dynamic provisioning; a functional provisioner must exist behind it.
- `WaitForFirstConsumer` can intentionally leave claims pending until Kubernetes knows where the workload will run.
- Persistent storage must be validated through destructive tests rather than assumed from resource status alone.
- `ReadWriteOnce` volumes require deployment behavior that avoids competing database instances.
- Database backups and persistent volumes address different recovery scenarios and should be implemented independently.
- MySQL command-line clients may use Unix sockets unless TCP is explicitly requested.
- Application readiness should validate the actual service rather than relying only on container state.
- Remote automation should avoid uncontrolled shell termination when diagnostic commands return non-zero.

## Troubleshooting Log

### Missing Kubernetes Context

The initial environment contained the kubectl client but no working cluster context.

Observed behavior:

~~text
The connection to the server localhost:8080 was refused
~~

The absence of a valid kubeconfig caused kubectl to fall back to an unusable local endpoint.

Resolution:

- Installed a single-node K3s cluster
- Restored kubeconfig from `/etc/rancher/k3s/k3s.yaml`
- Configured user ownership and permissions
- Verified Kubernetes API connectivity
- Verified node readiness

### Invalid Storage Provisioner

The initial storage configuration referenced:

~~text
kubernetes.io/host-path
~~

That value did not provide functioning dynamic provisioning in the validated environment.

Resolution:

- Detected the provisioner available through K3s
- Used the Rancher local-path provisioner
- Created the custom `fast-storage` StorageClass
- Used `WaitForFirstConsumer` binding behavior

### PVC Pending Before Consumption

A claim using `WaitForFirstConsumer` can remain pending until a consuming pod exists.

Resolution:

- Created the workload referencing the PVC
- Allowed Kubernetes to select the node
- Verified the claim transitioned to `Bound`

### MySQL Unix Socket Validation Failure

The initial MySQL health command attempted a Unix socket connection:

~~text
Can't connect to local MySQL server through socket
'/var/run/mysqld/mysqld.sock'
~~

Resolution:

Explicitly forced TCP:

~~bash
mysqladmin \
  --protocol=TCP \
  -h 127.0.0.1 \
  -P 3306
~~

### Remote Session Closed After Validation Failure

A diagnostic command returned a non-zero exit code while the remote shell was running with:

~~bash
set -e
~~

This terminated the active remote shell and closed the SSH connection.

Resolution:

- Replaced `set -e` with controlled error handling
- Wrapped sensitive execution sequences inside shell functions
- Used `return` instead of terminating the parent shell
- Preserved SSH connectivity after validation failures

### Deprecated Endpoints Resource

The Kubernetes cluster warned that the legacy `Endpoints` resource is deprecated.

Resolution:

Service backend inspection was changed to:

~~bash
kubectl get endpointslice \
  -l kubernetes.io/service-name=mysql-service
~~

### Sensitive Material Handling

The generated MySQL Secret manifest contains plaintext credential material after rendering, and database dump files contain application data.

These files must not be committed:

~~text
mysql-secret.yaml
*.sql
~~

## Security Notes

- Never commit rendered Kubernetes Secret manifests containing plaintext values.
- Never commit database backups containing operational data.
- Use external secret management for production credentials.
- Restrict hostPath or local-path storage to environments where node-local persistence is appropriate.
- Use distributed or cloud-backed storage for workloads requiring multi-node resilience.
