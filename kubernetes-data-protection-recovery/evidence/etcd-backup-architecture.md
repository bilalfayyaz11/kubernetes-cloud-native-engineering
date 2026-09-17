# Kubernetes etcd Backup Architecture

## Backup Path

```text
Kubernetes API Objects
        |
        v
       etcd
        |
        | authenticated local snapshot
        v
kind Control-Plane Node
        |
        | docker cp
        v
Protected Host Backup Directory
        |
        +--> etcd-snapshot-<timestamp>.db
        |
        +--> SHA-256 sidecar
```

## Credential Boundary

The etcd client uses:

```text
/etc/kubernetes/pki/etcd/ca.crt
/etc/kubernetes/pki/etcd/server.crt
/etc/kubernetes/pki/etcd/server.key
```

inside the kind control-plane node.

Private etcd key material is not copied into the working directory or backup package.

## Integrity Controls

Each snapshot receives:

```text
snapshot status validation
SHA-256 integrity hash
restricted host permissions
timestamped naming
retention cleanup
```

## Recovery Test Data

The snapshot contains a controlled namespace with:

```text
recovery-validation
recovery-marker ConfigMap
recovery-workload Deployment
```

These resources provide known state that can be checked during disaster-recovery testing.
