# Kubernetes Etcd Backup and Disaster Recovery

## Overview

This implementation demonstrates end-to-end Kubernetes control-plane disaster recovery using real etcd snapshots.

The environment was built from a fresh Ubuntu host, initialized as a kubeadm control plane, populated with application state, backed up using etcd snapshot tooling, deliberately modified to simulate state loss, and recovered from a known-good snapshot.

The workflow covers:

- Kubernetes control-plane bootstrap
- containerd CRI configuration
- Flannel CNI
- etcd static Pod discovery
- etcd topology inspection
- PKI-based etcd authentication
- live snapshot creation
- snapshot integrity verification
- SHA256 checksum generation
- destructive Kubernetes state-loss simulation
- control-plane shutdown
- preservation of post-failure etcd data
- snapshot restoration
- etcd revision bump
- restored-revision compaction marking
- API server recovery
- application-state verification
- resource fingerprint comparison
- automated etcd backups
- snapshot retention
- disaster-recovery health checks
- operational recovery documentation

---

## Architecture

~~text
                     Kubernetes API Server
                              |
                              v
                        +-----------+
                        |   etcd    |
                        | Cluster   |
                        |   State   |
                        +-----+-----+
                              |
                     Snapshot Backup
                              |
                              v
                  /opt/etcd-backup/*.db
                              |
                      Disaster Event
                              |
                              v
                    Kubernetes State Loss
                              |
                     Control Plane Stop
                              |
                              v
                    Snapshot Restoration
                              |
                  +-----------+------------+
                  |                        |
           Revision Bump             Mark Compacted
                  |                        |
                  +-----------+------------+
                              |
                              v
                      Restored etcd
                              |
                              v
                   Kubernetes API Server
                              |
                              v
                 Recovered Application State
~~

---

## Environment

The environment uses:

- Ubuntu 24.04
- Kubernetes v1.36
- kubeadm
- kubelet
- kubectl
- containerd
- crictl
- Flannel CNI
- etcd
- etcdctl
- etcdutl
- OpenSSL
- jq
- curl

The host initially contained no Kubernetes cluster, etcd data directory, etcd PKI, or control-plane components.

A complete control plane was therefore created before the disaster-recovery workflow began.

---

## Kubernetes Bootstrap

The cluster was initialized with kubeadm using:

~~text
CRI: containerd
Pod network: 10.244.0.0/16
Control plane: single node
CNI: Flannel
~~

containerd was configured with systemd cgroups and validated through the CRI interface before Kubernetes initialization.

Because the environment contains a single node, the control-plane scheduling taint was removed to permit application workloads.

---

## Etcd Architecture Discovery

The running etcd instance was inspected before any backup activity.

The workflow identified:

- etcd static Pod
- member name
- data directory
- client URLs
- peer URLs
- initial cluster configuration
- Kubernetes PKI paths
- etcd endpoint health
- member status
- active etcd release

Recovery parameters were derived from the actual static Pod manifest rather than hard-coded example values.

This is important because restore values such as:

~~text
--name
--initial-cluster
--initial-advertise-peer-urls
--data-dir
~~

must match the real control-plane configuration.

---

## Matching Etcd Tooling

The running etcd version was detected from the Kubernetes static Pod image.

Matching versions of:

~~text
etcdctl
etcdutl
~~

were installed under:

~~text
/usr/local/bin/
~~

Absolute binary paths are used by operational scripts to avoid differences between the normal user PATH and sudo's execution environment.

---

## Etcd Authentication

Administrative etcd operations use Kubernetes-generated TLS credentials.

The workflow uses:

~~text
/etc/kubernetes/pki/etcd/ca.crt
/etc/kubernetes/pki/etcd/healthcheck-client.crt
/etc/kubernetes/pki/etcd/healthcheck-client.key
~~

Endpoint health is verified before backup or recovery operations.

Example:

~~bash
sudo env ETCDCTL_API=3 \
  /usr/local/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint health
~~

---

## Recovery Test State

A dedicated namespace was created to provide deterministic state for backup and recovery validation.

~~text
Namespace:  backup-test
Deployment: nginx-deployment
Replicas:   3
Service:    nginx-service
ConfigMap:  test-config
Secret:     test-secret
~~

A unique recovery marker was written into the test state.

Example:

~~text
restore-marker-YYYYMMDD-HHMMSS
~~

That marker provides a strong proof that the restored resources came from the intended pre-failure state.

---

## Resource Fingerprinting

A compact resource fingerprint records the expected state before destructive testing.

~~text
namespace=backup-test
deployment=nginx-deployment
replicas=3
service=nginx-service
configmap=test-config
secret=test-secret
marker=<recovery-marker>
~~

After restoration, an equivalent fingerprint is generated and compared with `diff`.

An exact match confirms that the expected logical resource set returned.

---

## Etcd Snapshot Creation

Snapshots are created from the live etcd endpoint using:

~~bash
etcdctl snapshot save
~~

Snapshots are stored under:

~~text
/opt/etcd-backup/
~~

Example naming convention:

~~text
etcd-snapshot-YYYYMMDD-HHMMSS.db
~~

The snapshot database itself is treated as sensitive because etcd can contain Kubernetes Secret data.

It is never placed inside the repository.

---

## Snapshot Integrity Verification

Each snapshot is verified with:

~~bash
etcdutl snapshot status
~~

The workflow records:

- snapshot filename
- database size
- snapshot revision
- SHA256 checksum
- integrity status

Example:

~~bash
etcdutl snapshot status \
  /opt/etcd-backup/etcd-snapshot-*.db \
  --write-out=table
~~

---

## Snapshot Security

An etcd snapshot is effectively a backup of Kubernetes cluster state.

It may contain:

- Secret objects
- ConfigMaps
- RBAC configuration
- workload definitions
- ServiceAccounts
- cluster metadata
- admission configuration

For this reason:

- `.db` snapshots are excluded from Git
- Kubernetes PKI keys are excluded from Git
- kubeconfig credentials are excluded from Git
- Secret payloads are not written into recruiter-facing evidence
- only safe snapshot metadata is retained in the repository

---

## Failure Simulation

State loss was simulated by deleting:

~~text
namespace/backup-test
~~

Because deleting a namespace removes its namespaced resources, this removed:

- nginx Deployment
- nginx Pods
- nginx Service
- ConfigMap
- Secret

The Kubernetes control plane remained operational.

This isolates the exercise to an etcd state-recovery scenario without unnecessarily damaging unrelated system services.

---

## Failure Evidence

Before deletion, the environment records:

- resource inventory
- recovery marker
- etcd revision
- namespace state

After deletion, it records:

- namespace absence
- resource absence
- updated etcd revision
- healthy control-plane status

The etcd revision advancing after deletion confirms that destructive state changes were committed after the snapshot.

---

## Control-Plane Shutdown

For an etcd restore, static control-plane components are stopped by temporarily moving their manifests out of:

~~text
/etc/kubernetes/manifests/
~~

The shutdown sequence used is:

~~text
kube-apiserver
      |
      v
kube-controller-manager
      |
      v
kube-scheduler
      |
      v
etcd
~~

The kubelet automatically stops static Pods when their manifests disappear.

---

## Preserving Failed-State Data

Before replacing the etcd database, the existing data directory is preserved.

Conceptually:

~~text
/var/lib/etcd
      |
      v
/var/lib/etcd.pre-corrected-restore.<timestamp>
~~

This preserves the post-failure database for investigation or rollback.

The live data directory is never blindly deleted.

---

## Snapshot Restoration

The snapshot is restored using:

~~bash
etcdutl snapshot restore
~~

Restore parameters are derived from the real etcd configuration.

The recovery procedure uses:

~~text
--data-dir
--name
--initial-cluster
--initial-advertise-peer-urls
--initial-cluster-token
~~

This avoids assumptions about hostnames or member identities.

---

## Kubernetes Revision-Bump Recovery

Rolling Kubernetes etcd state backward requires special care.

Controllers and API clients may have previously observed revisions newer than those inside the snapshot.

The corrected restore therefore uses:

~~text
--bump-revision
--mark-compacted
~~

The revision bump moves restored etcd to a revision above the original snapshot revision.

Marking the restored revision compacted forces clients relying on older watch history to rebuild their state rather than silently assuming stale observations remain authoritative.

This provides a more robust Kubernetes rollback procedure than restoring an old revision without accounting for watcher state.

---

## Recovery Sequence

The final recovery sequence is:

~~text
Verify snapshot
      |
      v
Stop API server
      |
      v
Stop controller-manager
      |
      v
Stop scheduler
      |
      v
Stop etcd
      |
      v
Preserve current /var/lib/etcd
      |
      v
Restore snapshot
      |
      v
Apply revision bump
      |
      v
Mark restored revision compacted
      |
      v
Restart etcd
      |
      v
Verify etcd health
      |
      v
Restart API server
      |
      v
Restart controller-manager
      |
      v
Restart scheduler
      |
      v
Validate restored Kubernetes state
~~

---

## Etcd Recovery Validation

After restoration, the workflow verifies:

- etcd endpoint health
- etcd endpoint status
- etcd member list
- Kubernetes API readiness
- node Ready status
- control-plane Pods
- restored namespace
- restored Deployment
- 3 ready replicas
- restored Service
- EndpointSlice
- restored ConfigMap
- restored Secret
- recovery marker
- application connectivity

---

## Recovery Marker Validation

The same unique marker generated before the snapshot must exist after restoration.

The ConfigMap marker is compared against the locally recorded expected marker.

The Secret marker is also verified programmatically without writing its payload to evidence files.

This provides stronger verification than checking only whether similarly named resources exist.

---

## Application Recovery

The restored nginx Service is tested from an ephemeral Kubernetes client.

Conceptually:

~~text
Temporary client Pod
        |
        v
nginx-service
        |
        v
EndpointSlice
        |
        v
Restored nginx Pods
~~

Successful HTTP connectivity verifies that the recovered state is operational, not merely present in etcd.

---

## Automated Backup Script

The reusable script:

~~text
scripts/etcd-backup.sh
~~

performs:

1. etcd health validation
2. timestamped snapshot creation
3. snapshot integrity verification
4. SHA256 calculation
5. size capture
6. revision capture
7. metadata generation
8. retention enforcement

Example:

~~bash
RETENTION_DAYS=7 ./scripts/etcd-backup.sh
~~

---

## Retention Policy

Old snapshot databases and their metadata can be removed automatically according to the configured retention period.

Default:

~~text
7 days
~~

Retention can be changed with:

~~bash
RETENTION_DAYS=14 ./scripts/etcd-backup.sh
~~

Snapshot retention alone is not a complete production backup strategy.

Production backups should also be copied to durable, access-controlled storage outside the cluster.

---

## Backup Metadata

Each automated snapshot produces metadata containing:

~~text
timestamp
snapshot filename
size
SHA256
revision
retention period
security classification
repository policy
~~

The database itself remains outside source control.

---

## Final Recovery Health Check

The reusable script:

~~text
scripts/verify-etcd-recovery.sh
~~

checks:

- Kubernetes API readiness
- node readiness
- etcd endpoint health
- recovered namespace
- Deployment replica count
- restored Service
- ConfigMap recovery marker
- Secret existence
- application connectivity
- control-plane static manifests

The script returns a non-zero exit code when a required recovery check fails.

---

## Operational Runbook

The generated disaster-recovery runbook documents the complete process.

### Backup Procedure

~~text
1. Verify etcd health
2. Create snapshot
3. Verify snapshot integrity
4. Record checksum, revision, and size
5. Store snapshot securely
6. Enforce retention
7. Periodically perform restore tests
~~

### Recovery Procedure

~~text
1. Identify the intended snapshot
2. Capture live etcd topology
3. Stop static control-plane components
4. Preserve current etcd data
5. Restore snapshot
6. Apply Kubernetes-safe revision handling
7. Restart etcd
8. Verify etcd health
9. Restart API server
10. Restart remaining control-plane components
11. Verify Kubernetes resources
12. Validate application connectivity
13. Compare restored fingerprints
~~

---

## Evidence

Safe operational evidence includes:

~~text
evidence/
├── etcd-environment-evidence.txt
├── etcd-static-pod-parameters.txt
├── etcd-recovery-parameters.txt
├── etcd-discovery-evidence.txt
├── recovery-safety-notes.txt
├── recovery-marker.txt
├── pre-snapshot-state.txt
├── pre-snapshot-resource-fingerprint.txt
├── etcd-revision-before-snapshot.txt
├── etcd-snapshot-metadata.txt
├── etcd-snapshot-status.txt
├── etcd-snapshot-evidence.txt
├── final-pre-failure-state.txt
├── etcd-revision-before-deletion.txt
├── etcd-revision-after-deletion.txt
├── post-failure-state.txt
├── failure-comparison.txt
├── pre-restore-control-plane-state.txt
├── etcd-restore-evidence.txt
├── snapshot-content-diagnostic.txt
├── corrected-pre-restore-fingerprint.txt
├── corrected-post-restore-fingerprint.txt
├── corrected-fingerprint-diff.txt
├── corrected-etcd-recovery-evidence.txt
├── automated-backup-run.txt
├── final-recovery-health-report.txt
├── final-etcd-status.txt
├── final-etcd-member-list.txt
├── final-disaster-recovery-state.txt
└── etcd-disaster-recovery-runbook.txt
~~

Files are included only when they exist locally.

---

## Repository Structure

~~text
kubernetes-etcd-disaster-recovery/
├── README.md
├── manifests/
│   └── backup-test-state.yaml
├── scripts/
│   ├── etcd-backup.sh
│   └── verify-etcd-recovery.sh
└── evidence/
    ├── etcd-environment-evidence.txt
    ├── etcd-static-pod-parameters.txt
    ├── etcd-recovery-parameters.txt
    ├── etcd-discovery-evidence.txt
    ├── recovery-safety-notes.txt
    ├── recovery-marker.txt
    ├── pre-snapshot-state.txt
    ├── pre-snapshot-resource-fingerprint.txt
    ├── etcd-revision-before-snapshot.txt
    ├── etcd-snapshot-metadata.txt
    ├── etcd-snapshot-status.txt
    ├── etcd-snapshot-evidence.txt
    ├── final-pre-failure-state.txt
    ├── etcd-revision-before-deletion.txt
    ├── etcd-revision-after-deletion.txt
    ├── post-failure-state.txt
    ├── failure-comparison.txt
    ├── pre-restore-control-plane-state.txt
    ├── etcd-restore-evidence.txt
    ├── snapshot-content-diagnostic.txt
    ├── corrected-pre-restore-fingerprint.txt
    ├── corrected-post-restore-fingerprint.txt
    ├── corrected-fingerprint-diff.txt
    ├── corrected-etcd-recovery-evidence.txt
    ├── automated-backup-run.txt
    ├── final-recovery-health-report.txt
    ├── final-etcd-status.txt
    ├── final-etcd-member-list.txt
    ├── final-disaster-recovery-state.txt
    └── etcd-disaster-recovery-runbook.txt
~~

---

## Skills Demonstrated

- Kubernetes control-plane administration
- kubeadm
- containerd
- CRI troubleshooting
- Flannel CNI
- etcd architecture
- etcd static Pods
- etcd PKI
- etcdctl
- etcdutl
- etcd endpoint health
- etcd member inspection
- Kubernetes state backup
- snapshot integrity verification
- SHA256 verification
- disaster simulation
- control-plane shutdown
- etcd data preservation
- snapshot restoration
- revision bump recovery
- compaction marking
- Kubernetes API recovery
- state fingerprinting
- Secret-safe verification
- application recovery testing
- retention automation
- disaster-recovery runbook development

---

## Security Considerations

The following artifacts must never be committed:

~~text
*.db
*.snap
*.key
*.pem
admin.conf
kubeconfig files
Kubernetes PKI private keys
live kubeadm bootstrap tokens
etcd database directories
~~

Etcd snapshots are intentionally treated as sensitive even when the test workload contains no production credentials.

This is because snapshots represent the broader Kubernetes state database and may contain sensitive cluster objects.

---

## Operational Relevance

These procedures directly apply to:

- Kubernetes administration
- Site Reliability Engineering
- Platform engineering
- DevOps
- infrastructure operations
- control-plane incident response
- disaster-recovery planning
- business-continuity engineering
- production backup strategy

The central operational workflow demonstrated is:

~~text
Healthy Cluster
      |
      v
Create Snapshot
      |
      v
Verify Backup
      |
      v
State Loss
      |
      v
Preserve Failed State
      |
      v
Restore Etcd
      |
      v
Recover Control Plane
      |
      v
Validate Resources
      |
      v
Verify Application
~~

The key outcome is not simply creating an etcd snapshot, but demonstrating a tested procedure for recovering Kubernetes control-plane state and proving that deleted application resources return in a functional state.
