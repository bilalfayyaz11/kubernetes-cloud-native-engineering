# Kubernetes Data Protection and Disaster Recovery

A Kubernetes data-protection implementation focused on real persistent-storage encryption, etcd backup integrity, and disaster-recovery validation.

The architecture separates three independent concerns:

```text
Persistent Workload Data
        |
        v
Encryption at Rest

Kubernetes Control-Plane State
        |
        v
Verified etcd Backups

Failure / Data Loss
        |
        v
Tested Recovery Process
```

## Security Objectives

This implementation demonstrates:

```text
LUKS2 persistent-storage encryption
Kubernetes PV/PVC integration
raw-storage plaintext validation
authenticated etcd snapshots
SHA-256 snapshot integrity
backup freshness monitoring
isolated etcd restore
point-in-time recovery
post-incident integrity validation
```

## Persistent Storage Architecture

```text
Application Pod
      |
      v
PersistentVolumeClaim
      |
      v
PersistentVolume
      |
      v
Kind Node Mount
      |
      v
Unlocked ext4 Filesystem
      |
      v
Device Mapper
      |
      v
LUKS2 Encryption
      |
      v
Raw Encrypted Backing Storage
```

The application receives normal filesystem access through the decrypted layer.

The underlying backing storage remains encrypted.

## Why This Matters

A Kubernetes StorageClass label such as:

```yaml
encrypted: "true"
```

does not independently prove that workload data is encrypted.

This implementation validates encryption at the actual block-storage layer.

## Encryption Validation

A known marker is written through the Kubernetes PVC.

The same value is then tested at multiple layers:

```text
Kubernetes PVC                 READABLE
Unlocked filesystem            READABLE
Raw encrypted backing image    NOT READABLE
```

The raw block device reports:

```text
crypto_LUKS
```

while the unlocked device exposes:

```text
ext4
```

This confirms that the filesystem exists behind the encryption boundary.

## Encryption Key Boundary

The LUKS key is deliberately kept outside the repository.

```text
Repository
    |
    X
    |
LUKS Key
```

The key is:

```text
stored in a protected external directory
permission restricted
never printed
never committed
```

## Kubernetes Persistent Storage

The encrypted filesystem is exposed to the kind control-plane node and mapped into Kubernetes using a static PersistentVolume.

```text
PersistentVolume
        |
        v
PersistentVolumeClaim
        |
        v
Application Pod
```

The PV uses:

```text
Retain reclaim policy
explicit storage class
controlled host path
```

## etcd Backup Architecture

```text
Kubernetes Objects
       |
       v
      etcd
       |
       | authenticated snapshot
       v
Control-Plane Node
       |
       v
Protected Host Backup Directory
       |
       +--> snapshot database
       |
       +--> SHA-256 sidecar
```

## etcd Authentication

Snapshot creation uses the control-plane etcd PKI:

```text
etcd CA certificate
etcd server certificate
etcd server private key
```

Those credentials remain inside the control-plane node.

Private etcd key material is not copied into the repository.

## Backup Integrity

Each etcd snapshot is validated through multiple checks:

```text
endpoint health
snapshot creation result
snapshot structure
SHA-256 checksum
file permissions
backup age
```

The snapshot and checksum are stored outside the Git working tree.

## Backup Retention

The backup automation supports:

```text
timestamped snapshots
7-day cleanup policy
backup freshness checks
integrity sidecars
restricted file permissions
```

## Recovery Validation State

Before the backup, known Kubernetes resources are created:

```text
Namespace:
recovery-validation

ConfigMap:
recovery-marker

Expected marker:
PRE_INCIDENT_STATE

Deployment:
recovery-workload
```

These objects provide deterministic recovery evidence.

## Incident Simulation

The recovery workflow deliberately deletes pre-snapshot objects from the running cluster.

```text
recovery-marker       DELETED
recovery-workload     DELETED
```

A separate object is created after the backup:

```text
post-backup-only
```

This provides a point-in-time control.

## Isolated Disaster Recovery

The restore process does not overwrite the live Kubernetes control plane.

Instead:

```text
Verified Snapshot
       |
       v
Isolated Restore Directory
       |
       v
Temporary etcd Instance
       |
       v
Direct Recovery Validation
```

This makes the recovery exercise non-destructive.

## Point-in-Time Recovery

Expected restored state:

```text
recovery-marker       PRESENT
recovery-workload     PRESENT
post-backup-only      ABSENT
```

This validates that the snapshot represents the Kubernetes state at the moment the backup was created.

## Recovery Integrity

The restored etcd instance is queried directly to prove that deleted objects remain recoverable.

Validation covers:

```text
snapshot hash integrity
snapshot structural integrity
restored etcd health
ConfigMap recovery
Deployment recovery
point-in-time behavior
live-cluster health
```

## Recovery Point Objective

The implementation evaluates snapshot freshness against:

```text
RPO <= 24 hours
```

Production environments may require substantially shorter intervals depending on business impact and workload change frequency.

## Recovery Time Objective

A production RTO cannot be derived solely from a small local environment.

A complete production recovery timeline should include:

```text
incident detection
recovery decision
snapshot selection
integrity verification
etcd restore
control-plane restart
Kubernetes validation
workload validation
persistent-data validation
business-service validation
```

## Defense in Depth

The data-protection design separates multiple security boundaries.

```text
Workload Data
     |
     +--> LUKS encryption

Control-Plane State
     |
     +--> etcd snapshot

Backup Integrity
     |
     +--> SHA-256

Backup Access
     |
     +--> restricted filesystem permissions

Key Management
     |
     +--> external protected key location

Recovery
     |
     +--> isolated restore validation
```

## Repository Structure

```text
kubernetes-data-protection-recovery/
├── README.md
├── .gitignore
├── config/
│   └── kind.yaml
├── manifests/
│   ├── encrypted-persistent-storage.yaml
│   ├── storage-validation-pod.yaml
│   └── backup-validation-state.yaml
├── scripts/
│   ├── verify-storage-encryption.sh
│   ├── etcd-backup.sh
│   ├── backup-monitor.sh
│   └── validate-recovery.sh
└── evidence/
    ├── storage encryption validation
    ├── LUKS topology evidence
    ├── etcd health evidence
    ├── backup validation
    ├── snapshot status
    ├── restore validation
    ├── point-in-time recovery evidence
    └── final data-protection assessment
```

## Security Principles Demonstrated

### Encrypt the Data Layer

Encryption is applied at the actual storage layer rather than inferred from Kubernetes metadata.

### Protect Keys Separately

Encryption keys are kept outside the Git working tree and outside application manifests.

### Backups Must Be Verified

A backup file alone is not considered evidence of recoverability.

The workflow verifies:

```text
creation
integrity
structure
freshness
permissions
restore
```

### Test Recovery

Recovery procedures are validated before an actual incident.

### Validate Point-in-Time Semantics

Recovery is tested against both:

```text
objects that should exist
objects that should not exist
```

### Avoid Destructive Recovery Testing

The snapshot is restored into an isolated etcd instance rather than replacing live control-plane state.

## Production Extensions

A production-grade implementation could add:

```text
KMS or HSM-managed LUKS keys
CSI-based encrypted cloud volumes
KMS-backed Kubernetes Secret encryption
off-host backup storage
cross-region replication
immutable backups
object-lock retention
backup encryption
automated scheduled snapshots
multi-member etcd restore procedures
backup failure alerting
DR runbooks
scheduled recovery drills
RPO/RTO dashboards
```

## Key Takeaway

Data protection requires more than creating backups or attaching an encryption label.

The complete engineering lifecycle is:

```text
Encrypt
   |
   v
Write Data
   |
   v
Verify Raw Storage
   |
   v
Back Up Control Plane
   |
   v
Hash Snapshot
   |
   v
Simulate Failure
   |
   v
Restore
   |
   v
Validate Recovered State
```

The result is a tested Kubernetes data-protection and disaster-recovery design rather than an unverified backup procedure.
