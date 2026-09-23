# Kubernetes etcd Disaster Recovery

## What This Does

This implementation demonstrates a complete Kubernetes control-plane disaster recovery workflow using real etcd snapshots.

A single-control-plane kubeadm cluster is created with a locally hosted etcd static Pod. Kubernetes resources are deployed, the etcd datastore is backed up, critical resources are deliberately deleted, and the control plane is restored from the snapshot.

The workflow validates that Kubernetes objects return with their original identities and that the recovered cluster can continue accepting new workload changes.

It also includes reusable automation for:

- authenticated etcd snapshots
- snapshot integrity validation
- SHA256 verification
- backup metadata
- retention management
- controlled etcd restoration
- revision bumping
- post-restore health validation

## Architecture

```text
                         Kubernetes Control Plane
                                  |
                                  v
                         +------------------+
                         |   kube-apiserver |
                         +--------+---------+
                                  |
                                  v
                         +------------------+
                         |       etcd       |
                         | Kubernetes State |
                         +--------+---------+
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
             Live Datastore               Snapshot Backup
             /var/lib/etcd                     |
                                                v
                                      +------------------+
                                      | etcdctl snapshot |
                                      |      save        |
                                      +--------+---------+
                                               |
                                               v
                                      +------------------+
                                      | etcdutl validate |
                                      +--------+---------+
                                               |
                            Disaster           |
                               |               |
                               v               v
                    Delete Kubernetes     Restore Snapshot
                         Resources              |
                                               v
                                    New etcd Data Directory
                                               |
                                               v
                                    Restart Control Plane
                                               |
                                               v
                                      Validate Recovery
```

## Prerequisites

- Ubuntu 24.04 LTS or compatible Linux environment
- sudo access
- containerd
- Kubernetes installed with kubeadm
- kubelet
- kubectl
- etcdctl
- etcdutl
- jq
- curl
- SHA256 utilities
- Internet access during environment preparation

Validated architecture:

```text
1 kubeadm control-plane node
1 stacked etcd member
Flannel CNI
containerd runtime
```

## Setup & Installation

The Kubernetes control plane was initialized with kubeadm.

Example:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<CONTROL_PLANE_IP> \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock
```

The control plane uses a static etcd Pod whose configuration is stored at:

```text
/etc/kubernetes/manifests/etcd.yaml
```

The etcd PKI is stored under:

```text
/etc/kubernetes/pki/etcd/
```

The initial datastore is stored at:

```text
/var/lib/etcd
```

The restore workflow does not delete this datastore.

## How to Reproduce

### 1. Inspect etcd Configuration

Inspect the running etcd static Pod:

```bash
kubectl get pods \
  -n kube-system \
  -l component=etcd \
  -o wide
```

Inspect the manifest:

```bash
sudo grep -E \
  -- '--name=|--data-dir=|--advertise-client-urls=|--initial-advertise-peer-urls=|--cert-file=|--key-file=|--trusted-ca-file=' \
  /etc/kubernetes/manifests/etcd.yaml
```

The implementation dynamically derives:

- etcd endpoint
- CA certificate
- client certificate
- client key
- member name
- peer URL
- data directory
- running etcd version

This avoids hard-coded assumptions about control-plane configuration.

### 2. Verify etcd Health

Authenticated access uses:

```bash
etcdctl \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  endpoint health
```

Additional inspection includes:

```bash
etcdctl endpoint status --write-out=table
etcdctl member list --write-out=table
```

### 3. Create Recovery Validation Resources

The recovery workload contains:

```text
Namespace
  backup-test

Deployment
  test-app

ConfigMap
  test-config

Secret
  test-secret

Service
  test-app-service
```

The application is deployed with multiple replicas so workload recovery can be validated after restoring etcd.

The runtime Secret value is generated dynamically and is not stored in the repository.

### 4. Capture Original Kubernetes Object Identity

Before taking the snapshot, Kubernetes UIDs are recorded for:

- namespace
- Deployment
- ConfigMap
- Secret
- Service
- CoreDNS ConfigMap

This creates stronger restore evidence than checking resource names alone.

After restoration, the UIDs can be compared to prove that the original snapshot objects returned.

### 5. Create the etcd Snapshot

Create the snapshot:

```bash
sudo etcdctl \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  snapshot save /opt/etcd-backup/<snapshot>.db
```

The snapshot is then protected with restrictive file permissions.

### 6. Validate Snapshot Integrity

Use `etcdutl`:

```bash
sudo etcdutl \
  --write-out=table \
  snapshot status /opt/etcd-backup/<snapshot>.db
```

Additional metadata captured includes:

- snapshot hash
- revision
- key count
- database size
- etcd version
- creation timestamp

A SHA256 checksum is also generated:

```bash
sudo sha256sum \
  /opt/etcd-backup/<snapshot>.db
```

### 7. Simulate Disaster

The recovery validation namespace is deliberately deleted:

```bash
kubectl delete namespace backup-test
```

The CoreDNS ConfigMap is also removed:

```bash
kubectl delete configmap coredns \
  -n kube-system
```

The workflow explicitly verifies that both resources are absent before restoration.

The etcd revision after the destructive changes is recorded to prove that cluster state changed after the snapshot.

### 8. Stop Control-Plane Access During Restore

The kube-apiserver static Pod manifest is temporarily moved outside the monitored static Pod directory.

The etcd static Pod is stopped the same way.

This prevents active API writes while restoring the datastore.

### 9. Restore into a New etcd Data Directory

Rather than deleting the original datastore, the snapshot is restored into a new directory.

Example:

```text
/var/lib/etcd-restored
```

or:

```text
/var/lib/etcd-restored-YYYYMMDD_HHMMSS
```

The restore uses:

```bash
sudo etcdutl snapshot restore <snapshot> \
  --name "$ETCD_NAME" \
  --data-dir "$RESTORE_DIR" \
  --initial-cluster "$INITIAL_CLUSTER" \
  --initial-cluster-token "$INITIAL_CLUSTER_TOKEN" \
  --initial-advertise-peer-urls "$ETCD_PEER_URL" \
  --bump-revision 1000000000 \
  --mark-compacted
```

Revision bumping and compaction marking help Kubernetes controllers and informers correctly handle restored state.

### 10. Update the etcd Static Pod

The `etcd-data` hostPath in the static Pod manifest is changed to the restored datastore.

Conceptually:

```text
Before
/etc/kubernetes/manifests/etcd.yaml
        |
        +--> /var/lib/etcd

After
/etc/kubernetes/manifests/etcd.yaml
        |
        +--> /var/lib/etcd-restored
```

The original datastore remains preserved.

### 11. Restart the Control Plane

After restored etcd is healthy, the kube-apiserver static Pod manifest is returned.

Health is validated using:

```bash
kubectl get --raw='/readyz'
```

The node must return to:

```text
Ready
```

### 12. Verify Restored Kubernetes Resources

Recovery validation checks that the following return:

```text
namespace/backup-test
deployment/test-app
configmap/test-config
secret/test-secret
service/test-app-service
configmap/kube-system/coredns
```

The restored resource UIDs are compared with their pre-backup values.

Matching UIDs provide evidence that the resources were restored from the etcd snapshot rather than recreated manually.

### 13. Validate Application Functionality

Post-restore validation includes:

```text
Kubernetes API health
node readiness
etcd health
Deployment availability
Pod readiness
ConfigMap content
Secret key structure
CoreDNS configuration
cluster DNS
Service DNS
application HTTP connectivity
```

The Secret values themselves are never printed into repository artifacts.

### 14. Validate New Writes After Recovery

A new Kubernetes object is created after restoration.

This confirms that:

```text
API Server
    |
    v
Restored etcd
    |
    v
New Kubernetes state
```

is functioning normally.

### 15. Validate Post-Restore Cluster Operations

Normal cluster operations are tested after recovery.

These include:

- creating a new Deployment
- scaling the restored Deployment
- creating Services
- verifying workload availability
- verifying etcd revision advancement
- checking Pod counts
- comparing pre-disaster and post-restore state

### 16. Automated Backup

Run:

```bash
sudo /opt/etcd-backup/backup-etcd.sh
```

The automation performs:

1. etcd endpoint health validation
2. live snapshot creation
3. snapshot integrity validation
4. SHA256 checksum generation
5. snapshot metadata collection
6. backup retention cleanup

### 17. Backup Retention

The automated backup script retains backups for seven days.

Managed files include:

```text
etcd-backup-YYYYMMDD_HHMMSS.db
etcd-backup-YYYYMMDD_HHMMSS.db.sha256
etcd-backup-YYYYMMDD_HHMMSS.db.metadata
```

Actual snapshot database files are deliberately excluded from version control because etcd snapshots can contain Kubernetes Secrets and other sensitive cluster state.

### 18. Automated Restore Procedure

The restore utility requires explicit execution confirmation:

```bash
sudo ETCD_RESTORE_CONFIRM=YES \
  /opt/etcd-backup/restore-etcd.sh \
  /opt/etcd-backup/<snapshot>.db
```

Without the confirmation variable, the script exits before modifying the control plane.

The restore utility:

1. verifies snapshot integrity
2. verifies checksum when available
3. preserves the active datastore
4. stops kube-apiserver
5. stops etcd
6. restores into a new datastore
7. applies a revision bump
8. marks the restored revision compacted
9. updates the static Pod hostPath
10. starts restored etcd
11. checks etcd health
12. starts kube-apiserver
13. checks Kubernetes API readiness

## Tools Used

- Kubernetes
- kubeadm
- kubelet
- kubectl
- etcd
- etcdctl
- etcdutl
- containerd
- crictl
- Flannel
- Bash
- jq
- curl
- SHA256 utilities
- systemd

## Key Skills Demonstrated

- Kubernetes control-plane architecture
- stacked etcd administration
- kubeadm cluster initialization
- static Pod management
- etcd endpoint authentication
- PKI-aware administration
- etcd snapshot creation
- snapshot integrity verification
- checksum verification
- Kubernetes disaster simulation
- point-in-time cluster recovery
- safe datastore restoration
- etcd revision management
- Kubernetes object identity validation
- control-plane recovery
- CoreDNS restoration
- post-recovery workload validation
- cluster write-path validation
- backup automation
- restore automation
- retention management
- disaster-recovery documentation

## Real-World Use Case

Kubernetes stores cluster state inside etcd.

This includes objects such as:

```text
Deployments
Services
ConfigMaps
Secrets
Namespaces
RBAC
Custom Resources
Cluster configuration
```

Loss or corruption of etcd can therefore make an otherwise healthy compute environment unusable.

A production recovery process needs more than a backup command.

It should include:

```text
Snapshot creation
        |
        v
Integrity verification
        |
        v
Secure backup handling
        |
        v
Controlled restore
        |
        v
API recovery
        |
        v
Workload verification
        |
        v
Normal operations testing
```

Regular restore testing is important because an untested backup does not prove recoverability.

## Lessons Learned

- etcd is the source of truth for Kubernetes control-plane state.
- Snapshot creation and restoration are separate operational concerns.
- `etcdctl` can capture a live snapshot.
- `etcdutl` is appropriate for snapshot inspection and restore operations.
- etcd client access requires the correct endpoint and PKI material.
- Hard-coded certificate paths and member names should be avoided when they can be derived from the live manifest.
- Kubernetes object UIDs provide strong evidence that objects were truly restored.
- The API server should not continue writing state while etcd restoration is underway.
- Restoring into a new datastore is safer than immediately deleting the previous datastore.
- The etcd static Pod can be redirected to the restored datastore through its hostPath.
- Revision bumping helps Kubernetes consumers handle state rollback.
- CoreDNS restoration provides a useful system-level recovery test.
- Workload existence alone is not sufficient proof of successful recovery.
- DNS, Services, scaling, new object creation, and application traffic should also be validated.
- Backup integrity should be verified before any destructive restore procedure.
- Checksums provide an additional validation layer for snapshot files.
- Automated backup procedures should implement retention policies.
- Restore automation should require explicit operator confirmation.
- etcd snapshot databases should not be committed to source control because they can contain sensitive Kubernetes state.

## Troubleshooting Log

### Fresh Machine Had No Kubernetes Cluster

The starting environment contained kubectl, Docker, and containerd but no kubeadm control plane.

A real kubeadm control plane was created so the recovery workflow could operate on:

```text
/etc/kubernetes/manifests/etcd.yaml
/etc/kubernetes/pki/etcd/
/var/lib/etcd
```

rather than simulating etcd behavior inside an unrelated cluster type.

### etcd Tooling Was Missing

Neither `etcdctl` nor `etcdutl` was initially installed.

The etcd version was determined from the running Kubernetes etcd image and matching tooling was installed.

This avoided version mismatch between the datastore and administrative utilities.

### Hard-Coded etcd Values Avoided

The initial recovery procedure could have assumed values such as:

```text
https://127.0.0.1:2379
master
/var/lib/etcd
```

Instead, endpoint, member, peer URL, certificate, key, and data-directory values were derived from the actual static Pod configuration.

### Runtime Secret Protection

The recovery test required a Secret object.

A temporary value was generated at runtime rather than storing a reusable plaintext password in source-controlled manifests.

Repository artifacts expose only Secret metadata and key names.

### Snapshot Verification Modernized

Snapshot creation uses:

```text
etcdctl snapshot save
```

Snapshot inspection and restore use:

```text
etcdutl snapshot status
etcdutl snapshot restore
```

This separates live-cluster operations from offline snapshot operations.

### Original Datastore Preserved

The disaster recovery workflow does not immediately remove the existing etcd datastore.

The snapshot is restored into a separate directory and the static Pod is redirected to that datastore.

This leaves the previous datastore available as an additional rollback path.

### Control Plane Temporarily Unavailable

Stopping etcd makes the Kubernetes API unavailable.

This is expected during a single-member stacked-etcd recovery operation.

The workflow therefore uses container runtime inspection while the Kubernetes API is offline.

### Restored Resource Identity Verified

The test namespace and associated resources were deleted after the snapshot.

Following restore, the returned Kubernetes object UIDs were compared against their pre-backup UIDs.

This provided direct evidence that the historical snapshot state had been restored.

### CoreDNS Recovery Verified

The CoreDNS ConfigMap was deliberately deleted as an additional system-level failure.

After restoration, the original ConfigMap returned.

CoreDNS was restarted and DNS resolution was tested again.

### Post-Restore Writes Verified

A fresh Kubernetes object was successfully created after the restore.

This confirmed that the recovered API server and etcd datastore were not merely readable but could accept new state.

### Automated Backup Validated

The backup automation was executed after recovery.

The resulting snapshot was checked for:

```text
snapshot integrity
checksum validity
metadata
retention configuration
```

### Restore Safety Guard Verified

The reusable restore utility refuses to start a destructive restore unless:

```text
ETCD_RESTORE_CONFIRM=YES
```

is supplied explicitly.

This reduces the risk of accidentally initiating control-plane recovery.
