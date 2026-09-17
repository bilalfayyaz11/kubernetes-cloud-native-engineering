#!/usr/bin/env bash

set -u

CLUSTER="${CLUSTER:-data-protection}"
NODE="${CLUSTER}-control-plane"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.kubernetes-data-protection-backups}"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

CONTAINER_SNAPSHOT="/tmp/etcd-snapshot-${TIMESTAMP}.db"
HOST_SNAPSHOT="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"

mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

echo "===== ETCD BACKUP ====="
echo "Timestamp: $TIMESTAMP"
echo "Control plane: $NODE"

if ! docker inspect "$NODE" >/dev/null 2>&1; then
  echo "ERROR: control-plane container not found"
  exit 1
fi

echo
echo "Checking etcd endpoint..."

docker exec \
  "$NODE" \
  sh -c '
    ETCDCTL_API=3 \
    etcdctl \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key \
      endpoint health
  '

if [ "$?" -ne 0 ]; then
  echo "ERROR: etcd endpoint unhealthy"
  exit 1
fi

echo
echo "Saving snapshot inside control-plane node..."

docker exec \
  "$NODE" \
  sh -c "
    rm -f '${CONTAINER_SNAPSHOT}'

    ETCDCTL_API=3 \
    etcdctl \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key \
      snapshot save '${CONTAINER_SNAPSHOT}'
  "

if [ "$?" -ne 0 ]; then
  echo "ERROR: etcd snapshot creation failed"
  exit 1
fi

echo
echo "Copying snapshot to protected host backup directory..."

docker cp \
  "${NODE}:${CONTAINER_SNAPSHOT}" \
  "$HOST_SNAPSHOT"

if [ "$?" -ne 0 ]; then
  echo "ERROR: snapshot copy failed"
  exit 1
fi

chmod 0600 \
  "$HOST_SNAPSHOT"

docker exec \
  "$NODE" \
  rm -f \
  "$CONTAINER_SNAPSHOT"

echo
echo "Snapshot:"
echo "$HOST_SNAPSHOT"

echo
echo "SHA-256:"

sha256sum \
  "$HOST_SNAPSHOT" \
  | tee "${HOST_SNAPSHOT}.sha256"

chmod 0600 \
  "${HOST_SNAPSHOT}.sha256"

echo
echo "Size:"

du -h \
  "$HOST_SNAPSHOT"

echo
echo "Removing snapshots older than 7 days..."

find "$BACKUP_DIR" \
  -maxdepth 1 \
  -type f \
  -name 'etcd-snapshot-*.db' \
  -mtime +7 \
  -delete

find "$BACKUP_DIR" \
  -maxdepth 1 \
  -type f \
  -name 'etcd-snapshot-*.db.sha256' \
  -mtime +7 \
  -delete

echo
echo "Backup complete:"
echo "$HOST_SNAPSHOT"
