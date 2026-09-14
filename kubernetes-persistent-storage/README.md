# Kubernetes Persistent Storage

## Overview

This implementation demonstrates persistent data management in Kubernetes using manually provisioned PersistentVolumes, PersistentVolumeClaims, mounted application storage, multiple claims in a single workload, persistence validation, and storage troubleshooting.

The workflow proves that application Pods can be deleted or recreated without losing data stored on a PersistentVolume.

## Architecture

~~text
                 Kubernetes Cluster
                        │
             ┌──────────┴──────────┐
             │                     │
             ▼                     ▼
        primary-pv             secondary-pv
           1Gi                    2Gi
        Retain                  Retain
             │                     │
             ▼                     ▼
       primary-pvc            secondary-pvc
          500Mi                   1Gi
             │                     │
             │       ┌─────────────┘
             │       │
             ▼       ▼
      ┌─────────────────────┐
      │ multi-volume-writer │
      │                     │
      │ /data1 ← primary    │
      │ /data2 ← secondary  │
      └─────────────────────┘

             primary-pvc
                  │
                  ▼
          ┌──────────────┐
          │ storage-writer│
          │              │
          │ /data        │
          └──────────────┘
                  │
                  ▼
         timestamps.log
         test-file.txt
~~

## Core Concepts Demonstrated

- PersistentVolume provisioning
- PersistentVolumeClaim binding
- `ReadWriteOnce` access mode
- `Retain` reclaim policy
- `hostPath` backing storage for single-node Kubernetes
- Persistent data across Pod recreation
- Persistent data across scale-to-zero and scale-up
- Multiple PVCs mounted into one workload
- Storage capacity troubleshooting
- Storage monitoring and event inspection

## Namespace

Create the namespace:

~~bash
kubectl create namespace persistent-storage
~~

## Primary PersistentVolume

~~bash
kubectl apply -f persistent-volume.yaml
kubectl get pv primary-pv
~~

The volume provides `1Gi` of storage and uses the `Retain` reclaim policy.

## Primary PersistentVolumeClaim

~~bash
kubectl apply -f persistent-volume-claim.yaml

kubectl get pvc \
  -n persistent-storage
~~

The claim requests `500Mi`, which can be satisfied by the `1Gi` PersistentVolume.

Expected state:

~~text
primary-pv    Bound
primary-pvc   Bound
~~

## Persistent Data Writer

Deploy the workload:

~~bash
kubectl apply -f storage-app-deployment.yaml

kubectl wait \
  --for=condition=Ready \
  pod \
  -l app=storage-writer \
  -n persistent-storage \
  --timeout=120s
~~

The container writes a timestamp into:

~~text
/data/timestamps.log
~~

every 30 seconds.

Verify data:

~~bash
POD=$(kubectl get pods \
  -n persistent-storage \
  -l app=storage-writer \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec \
  -n persistent-storage \
  "$POD" \
  -- cat /data/timestamps.log
~~

## Persistence Validation

Capture the current entry count:

~~bash
INITIAL_COUNT=$(kubectl exec \
  -n persistent-storage \
  "$POD" \
  -- wc -l /data/timestamps.log \
  | awk '{print $1}')
~~

Delete the workload:

~~bash
kubectl delete deployment storage-writer \
  -n persistent-storage
~~

Recreate it:

~~bash
kubectl apply -f storage-app-deployment.yaml
~~

Retrieve the new Pod and verify the existing file:

~~bash
NEW_POD=$(kubectl get pods \
  -n persistent-storage \
  -l app=storage-writer \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec \
  -n persistent-storage \
  "$NEW_POD" \
  -- cat /data/timestamps.log
~~

The Pod identity changes, but the data remains available because it resides on persistent storage rather than the container filesystem.

## Scale-to-Zero Persistence Test

Create explicit persistent data:

~~bash
kubectl exec \
  -n persistent-storage \
  "$NEW_POD" \
  -- sh -c 'echo "Persistence validation" > /data/test-file.txt'
~~

Scale down:

~~bash
kubectl scale deployment storage-writer \
  -n persistent-storage \
  --replicas=0
~~

Scale back up:

~~bash
kubectl scale deployment storage-writer \
  -n persistent-storage \
  --replicas=1
~~

Verify:

~~bash
FINAL_POD=$(kubectl get pods \
  -n persistent-storage \
  -l app=storage-writer \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec \
  -n persistent-storage \
  "$FINAL_POD" \
  -- cat /data/test-file.txt
~~

## Multi-Volume Workload

Create the second storage pair:

~~bash
kubectl apply -f additional-pv.yaml
kubectl apply -f additional-pvc.yaml
~~

Deploy the workload:

~~bash
kubectl apply -f multi-volume-app.yaml
~~

The container mounts:

~~text
primary-pvc   → /data1
secondary-pvc → /data2
~~

This demonstrates a single Kubernetes workload consuming multiple independent persistent storage resources.

## Unsatisfied Claim Troubleshooting

Apply:

~~bash
kubectl apply -f oversized-pvc.yaml
~~

The claim requests `10Gi`, while no matching available manual PersistentVolume has enough capacity.

Inspect:

~~bash
kubectl get pvc oversized-pvc \
  -n persistent-storage

kubectl describe pvc oversized-pvc \
  -n persistent-storage
~~

Expected state:

~~text
Pending
~~

This demonstrates how Kubernetes leaves a claim unbound when no compatible PersistentVolume satisfies its storage class, access mode, and capacity requirements.

## Storage Monitoring

Run:

~~bash
./monitor-storage.sh
~~

The script reports:

- PersistentVolumes
- PersistentVolumeClaims
- Mounted filesystem usage
- Files stored on the mounted volume
- PersistentVolume events
- PersistentVolumeClaim events

## Troubleshooting Patterns

### PVC remains Pending

Inspect:

~~bash
kubectl describe pvc <claim-name>
kubectl get events \
  --field-selector involvedObject.name=<claim-name>
~~

Common causes include:

- No compatible PersistentVolume
- Insufficient capacity
- StorageClass mismatch
- Access-mode mismatch

### Pod cannot mount storage

Check:

~~bash
kubectl describe pod <pod-name>
kubectl get pvc -n persistent-storage
kubectl get pv
~~

Confirm that the claim is `Bound` and referenced correctly by the workload.

### Data disappears after Pod recreation

Check whether the workload is using:

~~text
emptyDir
~~

instead of a PersistentVolumeClaim, and verify that the intended PVC is actually mounted at the expected path.

## Reclaim Policy

Both manually provisioned PersistentVolumes use:

~~text
persistentVolumeReclaimPolicy: Retain
~~

Deleting a claim therefore does not automatically treat the underlying storage as disposable.

This is useful when data preservation is more important than automatic cleanup, but retained volumes require deliberate lifecycle management.

## Production Considerations

`hostPath` is intentionally used here for single-node Kubernetes.

For production environments, prefer storage backed by an appropriate CSI driver such as:

- cloud block storage
- network-attached storage
- distributed storage platforms
- managed Kubernetes storage services

Production storage architecture should also account for:

- backups
- restore procedures
- snapshots
- encryption at rest
- access controls
- capacity monitoring
- failure domains
- disaster recovery

## Skills Demonstrated

- Kubernetes persistent storage architecture
- PersistentVolume provisioning
- PersistentVolumeClaim lifecycle
- Claim-to-volume binding
- Persistent filesystem mounts
- Data durability validation
- Multi-volume workload configuration
- Reclaim policy behavior
- Storage monitoring
- Kubernetes event inspection
- Storage failure diagnosis
- Capacity mismatch troubleshooting
