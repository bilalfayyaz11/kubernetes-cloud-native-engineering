# Kubernetes Data Protection Architecture

## Persistent Data

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
Unlocked Filesystem
      |
      v
LUKS2 Encryption
      |
      v
Encrypted Block Storage
```

Security property:

```text
plaintext available to authorized workload
plaintext unavailable in raw backing storage
```

## Kubernetes Control-Plane State

```text
Kubernetes Resources
       |
       v
      etcd
       |
       v
Authenticated Snapshot
       |
       v
Protected Backup Directory
       |
       +--> snapshot
       +--> SHA-256
```

## Disaster Recovery

```text
Verified Snapshot
       |
       v
Isolated Restore
       |
       v
Temporary etcd
       |
       v
Recovered Object Validation
```

## Security Boundaries

The design intentionally separates:

```text
workload data
control-plane metadata
encryption keys
backup artifacts
recovery evidence
```

Encryption keys and etcd private keys are excluded from the project directory.
