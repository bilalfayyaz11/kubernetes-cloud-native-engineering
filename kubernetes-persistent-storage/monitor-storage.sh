#!/bin/bash

set -u

NAMESPACE="persistent-storage"

echo "=== Kubernetes Storage Monitoring ==="
echo "Date: $(date)"
echo

echo "=== PersistentVolumes ==="
kubectl get pv -o wide
echo

echo "=== PersistentVolumeClaims ==="
kubectl get pvc -n "$NAMESPACE" -o wide
echo

POD_NAME=$(kubectl get pods \
  -n "$NAMESPACE" \
  -l app=storage-writer \
  -o jsonpath='{.items[0].metadata.name}' \
  2>/dev/null)

echo "=== Mounted Storage ==="

if [ -n "$POD_NAME" ]; then
    echo "Pod: $POD_NAME"

    kubectl exec \
      -n "$NAMESPACE" \
      "$POD_NAME" \
      -- df -h /data || true

    echo
    kubectl exec \
      -n "$NAMESPACE" \
      "$POD_NAME" \
      -- ls -lah /data || true
else
    echo "No storage-writer Pod found"
fi

echo
echo "=== PersistentVolume Events ==="

kubectl get events \
  --all-namespaces \
  --field-selector involvedObject.kind=PersistentVolume \
  --sort-by=.metadata.creationTimestamp \
  | tail -n 10 || true

echo
echo "=== PersistentVolumeClaim Events ==="

kubectl get events \
  -n "$NAMESPACE" \
  --field-selector involvedObject.kind=PersistentVolumeClaim \
  --sort-by=.metadata.creationTimestamp \
  | tail -n 10 || true
