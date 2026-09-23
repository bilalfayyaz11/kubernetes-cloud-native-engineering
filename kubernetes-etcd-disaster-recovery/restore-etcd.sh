#!/usr/bin/env bash

set +e

WORKDIR="/home/ubuntu/kubernetes-disaster-recovery"
STATIC_DIR="/etc/kubernetes/manifests"
HOLD_DIR="/etc/kubernetes/recovery-static-pods"
ENV_FILE="$WORKDIR/etcd-environment.sh"

if [ "$#" -ne 1 ]; then
  echo "Usage:"
  echo "sudo ETCD_RESTORE_CONFIRM=YES $0 /opt/etcd-backup/<snapshot>.db"
  echo
  echo "Available snapshots:"
  ls -lh /opt/etcd-backup/etcd-backup-*.db 2>/dev/null || true
  exit 1
fi

BACKUP_FILE="$1"

echo "=================================================="
echo " ETCD RESTORE PROCEDURE"
echo "=================================================="

if [ ! -s "$BACKUP_FILE" ]; then
  echo "FAIL: backup file not found: $BACKUP_FILE"
  exit 1
fi

if [ ! -s "$ENV_FILE" ]; then
  echo "FAIL: etcd environment file missing"
  exit 1
fi

source "$ENV_FILE"

for binary in etcdctl etcdutl crictl kubectl; do
  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "FAIL: required binary missing: $binary"
    exit 1
  fi
done

echo
echo "===== VALIDATE SNAPSHOT ====="

etcdutl \
  --write-out=table \
  snapshot status "$BACKUP_FILE"

if [ $? -ne 0 ]; then
  echo "FAIL: snapshot validation failed"
  exit 1
fi

if [ -f "${BACKUP_FILE}.sha256" ]; then
  echo
  echo "===== VERIFY CHECKSUM ====="

  cd "$(dirname "$BACKUP_FILE")" || exit 1

  sha256sum \
    -c "$(basename "${BACKUP_FILE}.sha256")"

  if [ $? -ne 0 ]; then
    echo "FAIL: snapshot checksum mismatch"
    exit 1
  fi

  cd "$WORKDIR" || exit 1
fi

echo
echo "===== VERIFY STATIC POD MANIFESTS ====="

for file in \
  "$STATIC_DIR/etcd.yaml" \
  "$STATIC_DIR/kube-apiserver.yaml"; do

  if [ ! -f "$file" ]; then
    echo "FAIL: missing $file"
    exit 1
  fi

  echo "PASS: $file"
done

INITIAL_CLUSTER="$(
  grep \
    -- '--initial-cluster=' \
    "$STATIC_DIR/etcd.yaml" \
  | head -n 1 \
  | sed 's/.*--initial-cluster=//' \
  | sed 's/"//g'
)"

if [ -z "$INITIAL_CLUSTER" ]; then
  echo "FAIL: unable to derive initial cluster configuration"
  exit 1
fi

INITIAL_CLUSTER_TOKEN="$(
  grep \
    -- '--initial-cluster-token=' \
    "$STATIC_DIR/etcd.yaml" \
  | head -n 1 \
  | sed 's/.*--initial-cluster-token=//' \
  | sed 's/"//g'
)"

if [ -z "$INITIAL_CLUSTER_TOKEN" ]; then
  INITIAL_CLUSTER_TOKEN="etcd-restore-$(date +%s)"
fi

RESTORE_ID="$(date +%Y%m%d_%H%M%S)"
RESTORE_DIR="/var/lib/etcd-restored-${RESTORE_ID}"
MANIFEST_BACKUP_DIR="$WORKDIR/restore-${RESTORE_ID}-manifests"

mkdir -p "$MANIFEST_BACKUP_DIR"
mkdir -p "$HOLD_DIR"

cp \
  "$STATIC_DIR/etcd.yaml" \
  "$MANIFEST_BACKUP_DIR/etcd.yaml"

cp \
  "$STATIC_DIR/kube-apiserver.yaml" \
  "$MANIFEST_BACKUP_DIR/kube-apiserver.yaml"

echo
echo "Backup file: $BACKUP_FILE"
echo "Restore directory: $RESTORE_DIR"
echo "Member: $ETCD_NAME"
echo "Peer URL: $ETCD_PEER_URL"

echo
echo "WARNING:"
echo "This operation temporarily stops kube-apiserver and etcd."
echo "The currently active datastore will not be deleted."

if [ "${ETCD_RESTORE_CONFIRM:-}" != "YES" ]; then
  echo
  echo "Restore not started."
  echo "Explicit confirmation variable is required:"
  echo
  echo "sudo ETCD_RESTORE_CONFIRM=YES $0 $BACKUP_FILE"
  exit 2
fi

echo
echo "===== STOP KUBE-APISERVER ====="

rm -f "$HOLD_DIR/kube-apiserver.yaml"

mv \
  "$STATIC_DIR/kube-apiserver.yaml" \
  "$HOLD_DIR/kube-apiserver.yaml"

APISERVER_STOPPED=0

for i in $(seq 1 30); do
  if crictl \
      --runtime-endpoint unix:///run/containerd/containerd.sock \
      ps \
      --name kube-apiserver \
      --quiet \
      2>/dev/null \
      | grep -q .; then

    echo "Waiting for kube-apiserver... $i/30"
    sleep 2
  else
    echo "PASS: kube-apiserver stopped"
    APISERVER_STOPPED=1
    break
  fi
done

if [ "$APISERVER_STOPPED" -ne 1 ]; then
  echo "FAIL: kube-apiserver failed to stop"

  mv \
    "$HOLD_DIR/kube-apiserver.yaml" \
    "$STATIC_DIR/kube-apiserver.yaml" \
    2>/dev/null || true

  exit 1
fi

echo
echo "===== STOP ETCD ====="

rm -f "$HOLD_DIR/etcd.yaml"

mv \
  "$STATIC_DIR/etcd.yaml" \
  "$HOLD_DIR/etcd.yaml"

ETCD_STOPPED=0

for i in $(seq 1 30); do
  if crictl \
      --runtime-endpoint unix:///run/containerd/containerd.sock \
      ps \
      --name etcd \
      --quiet \
      2>/dev/null \
      | grep -q .; then

    echo "Waiting for etcd... $i/30"
    sleep 2
  else
    echo "PASS: etcd stopped"
    ETCD_STOPPED=1
    break
  fi
done

if [ "$ETCD_STOPPED" -ne 1 ]; then
  echo "FAIL: etcd failed to stop"

  mv \
    "$HOLD_DIR/etcd.yaml" \
    "$STATIC_DIR/etcd.yaml" \
    2>/dev/null || true

  mv \
    "$HOLD_DIR/kube-apiserver.yaml" \
    "$STATIC_DIR/kube-apiserver.yaml" \
    2>/dev/null || true

  exit 1
fi

echo
echo "===== RESTORE SNAPSHOT ====="

etcdutl snapshot restore "$BACKUP_FILE" \
  --name "$ETCD_NAME" \
  --data-dir "$RESTORE_DIR" \
  --initial-cluster "$INITIAL_CLUSTER" \
  --initial-cluster-token "$INITIAL_CLUSTER_TOKEN" \
  --initial-advertise-peer-urls "$ETCD_PEER_URL" \
  --bump-revision 1000000000 \
  --mark-compacted

if [ $? -ne 0 ]; then
  echo "FAIL: snapshot restore failed"

  mv \
    "$HOLD_DIR/etcd.yaml" \
    "$STATIC_DIR/etcd.yaml" \
    2>/dev/null || true

  mv \
    "$HOLD_DIR/kube-apiserver.yaml" \
    "$STATIC_DIR/kube-apiserver.yaml" \
    2>/dev/null || true

  exit 1
fi

echo
echo "===== PREPARE RESTORED ETCD MANIFEST ====="

RESTORED_MANIFEST="$WORKDIR/etcd-restore-${RESTORE_ID}.yaml"

cp \
  "$MANIFEST_BACKUP_DIR/etcd.yaml" \
  "$RESTORED_MANIFEST"

CURRENT_HOST_PATH="$(
  grep -A 6 \
    'name: etcd-data' \
    "$RESTORED_MANIFEST" \
  | grep 'path:' \
  | head -n 1 \
  | awk '{print $2}'
)"

if [ -z "$CURRENT_HOST_PATH" ]; then
  echo "FAIL: unable to derive current etcd hostPath"
  exit 1
fi

echo "Current manifest hostPath: $CURRENT_HOST_PATH"
echo "New manifest hostPath: $RESTORE_DIR"

sed -i \
  "s#path: ${CURRENT_HOST_PATH}#path: ${RESTORE_DIR}#" \
  "$RESTORED_MANIFEST"

if ! grep -q \
    "path: ${RESTORE_DIR}" \
    "$RESTORED_MANIFEST"; then

  echo "FAIL: failed to update restored etcd hostPath"
  exit 1
fi

cp \
  "$RESTORED_MANIFEST" \
  "$STATIC_DIR/etcd.yaml"

chmod 600 "$STATIC_DIR/etcd.yaml"

echo
echo "===== WAIT FOR RESTORED ETCD ====="

ETCD_UP=0

for i in $(seq 1 60); do
  if crictl \
      --runtime-endpoint unix:///run/containerd/containerd.sock \
      ps \
      --name etcd \
      --quiet \
      2>/dev/null \
      | grep -q .; then

    echo "PASS: restored etcd container running"
    ETCD_UP=1
    break
  fi

  echo "Waiting for etcd... $i/60"
  sleep 2
done

if [ "$ETCD_UP" -ne 1 ]; then
  echo "FAIL: restored etcd failed to start"
  exit 1
fi

echo
echo "===== VERIFY RESTORED ETCD HEALTH ====="

ETCD_HEALTHY=0

for i in $(seq 1 30); do
  env \
    ETCDCTL_API=3 \
    etcdctl \
    --endpoints="$ETCD_ENDPOINT" \
    --cacert="$ETCD_CACERT" \
    --cert="$ETCD_CERT" \
    --key="$ETCD_KEY" \
    endpoint health \
    >/tmp/etcd-restore-health.txt \
    2>&1

  if [ $? -eq 0 ]; then
    cat /tmp/etcd-restore-health.txt
    ETCD_HEALTHY=1
    break
  fi

  echo "Waiting for etcd health... $i/30"
  sleep 2
done

if [ "$ETCD_HEALTHY" -ne 1 ]; then
  echo "FAIL: restored etcd unhealthy"
  exit 1
fi

echo
echo "===== RESTART KUBE-APISERVER ====="

mv \
  "$HOLD_DIR/kube-apiserver.yaml" \
  "$STATIC_DIR/kube-apiserver.yaml"

API_READY=0

for i in $(seq 1 60); do
  if kubectl get --raw='/readyz' \
      --request-timeout=5s \
      >/dev/null 2>&1; then

    echo "PASS: Kubernetes API ready"
    API_READY=1
    break
  fi

  echo "Waiting for Kubernetes API... $i/60"
  sleep 2
done

if [ "$API_READY" -ne 1 ]; then
  echo "FAIL: Kubernetes API did not recover"
  exit 1
fi

echo
echo "===== FINAL RESTORE HEALTH ====="

kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide

env \
  ETCDCTL_API=3 \
  etcdctl \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  endpoint status \
  --write-out=table

echo
echo "=================================================="
echo " ETCD RESTORE COMPLETE"
echo "=================================================="
