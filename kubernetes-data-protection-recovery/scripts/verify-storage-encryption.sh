#!/usr/bin/env bash

set -u

IMAGE="$HOME/.kubernetes-data-protection-storage.img"
MAPPER="/dev/mapper/k8s-secure-storage"
MOUNTPOINT="/mnt/k8s-secure-storage"

echo "===== STORAGE ENCRYPTION VERIFICATION ====="

echo
echo "Raw image:"
ls -lh "$IMAGE"

echo
echo "Mapper:"
if [ -b "$MAPPER" ]; then
  echo "PASS: mapper available"
else
  echo "FAIL: mapper missing"
fi

echo
echo "Mount:"
if mountpoint -q "$MOUNTPOINT"; then
  echo "PASS: encrypted filesystem mounted"
else
  echo "FAIL: encrypted filesystem not mounted"
fi

echo
echo "Kubernetes PVC:"
kubectl get pvc \
  secure-persistent-pvc \
  -n data-protection

echo
echo "Kubernetes workload:"
kubectl get pod \
  storage-validation \
  -n data-protection

echo
echo "Raw block type:"
LOOP_DEVICE=$(
  losetup -j "$IMAGE" \
    | cut -d: -f1 \
    | head -1
)

if [ -n "$LOOP_DEVICE" ]; then
  sudo blkid "$LOOP_DEVICE"
else
  echo "Loop device not found"
fi
