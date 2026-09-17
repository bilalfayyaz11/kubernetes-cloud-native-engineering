# Encrypted Kubernetes Persistent Storage

## Architecture

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
/secure-persistent-data
      |
      v
Kind Node Mount
      |
      v
Host Decrypted Mount
      |
      v
/dev/mapper/k8s-secure-storage
      |
      v
LUKS2 Encryption
      |
      v
Loop Device
      |
      v
Encrypted Backing Image
```

## Security Property

Kubernetes receives normal filesystem access through the unlocked layer.

The raw storage layer remains encrypted.

This separates:

```text
Application filesystem access
             from
Underlying block-storage representation
```

## Validation

A known marker was written through the Kubernetes PVC.

The marker was:

```text
Readable through the mounted PVC
Readable through the unlocked host filesystem
Not discoverable in the raw encrypted backing image
```

This demonstrates actual encryption of persistent workload data rather than relying on a StorageClass annotation.
