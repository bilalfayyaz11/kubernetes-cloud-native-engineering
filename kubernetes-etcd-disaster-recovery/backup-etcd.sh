#!/usr/bin/env bash

set +e

BACKUP_DIR="/opt/etcd-backup"
ENV_FILE="/home/ubuntu/kubernetes-disaster-recovery/etcd-environment.sh"
RETENTION_DAYS=7

echo "=================================================="
echo " ETCD AUTOMATED BACKUP"
echo "=================================================="

if [ ! -s "$ENV_FILE" ]; then
  echo "FAIL: etcd environment file missing: $ENV_FILE"
  exit 1
fi

source "$ENV_FILE"

for binary in etcdctl etcdutl sha256sum jq; do
  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "FAIL: required binary missing: $binary"
    exit 1
  fi
done

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

BACKUP_DATE="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/etcd-backup-${BACKUP_DATE}.db"

echo
echo "===== VERIFY ETCD HEALTH ====="

env \
  ETCDCTL_API=3 \
  etcdctl \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  endpoint health

if [ $? -ne 0 ]; then
  echo "FAIL: etcd endpoint unhealthy"
  exit 1
fi

echo
echo "===== CREATE SNAPSHOT ====="

env \
  ETCDCTL_API=3 \
  etcdctl \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  snapshot save "$BACKUP_FILE"

if [ $? -ne 0 ]; then
  echo "FAIL: snapshot creation failed"
  rm -f "$BACKUP_FILE"
  exit 1
fi

chmod 600 "$BACKUP_FILE"

echo
echo "===== VALIDATE SNAPSHOT ====="

etcdutl \
  --write-out=table \
  snapshot status "$BACKUP_FILE"

if [ $? -ne 0 ]; then
  echo "FAIL: snapshot validation failed"
  rm -f "$BACKUP_FILE"
  exit 1
fi

echo
echo "===== CREATE CHECKSUM ====="

sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"
chmod 600 "${BACKUP_FILE}.sha256"

if ! sha256sum \
  -c "${BACKUP_FILE}.sha256" \
  >/dev/null 2>&1; then

  echo "FAIL: checksum validation failed"

  rm -f \
    "$BACKUP_FILE" \
    "${BACKUP_FILE}.sha256"

  exit 1
fi

echo "PASS: checksum verified"

echo
echo "===== CAPTURE SNAPSHOT METADATA ====="

SNAPSHOT_JSON="$(
  etcdutl \
    --write-out=json \
    snapshot status "$BACKUP_FILE"
)"

SNAPSHOT_REVISION="$(
  echo "$SNAPSHOT_JSON" \
  | jq -r '.revision // empty'
)"

SNAPSHOT_HASH="$(
  echo "$SNAPSHOT_JSON" \
  | jq -r '.hash // empty'
)"

SNAPSHOT_KEYS="$(
  echo "$SNAPSHOT_JSON" \
  | jq -r '.totalKey // .totalKeys // empty'
)"

cat > "${BACKUP_FILE}.metadata" <<META
backup_file=$BACKUP_FILE
created=$(date -Is)
etcd_version=$ETCD_VERSION
endpoint=$ETCD_ENDPOINT
member_name=$ETCD_NAME
revision=${SNAPSHOT_REVISION:-unknown}
hash=${SNAPSHOT_HASH:-unknown}
keys=${SNAPSHOT_KEYS:-unknown}
META

chmod 600 "${BACKUP_FILE}.metadata"

echo
echo "===== APPLY RETENTION POLICY ====="

find "$BACKUP_DIR" \
  -type f \
  \( \
    -name 'etcd-backup-*.db' \
    -o -name 'etcd-backup-*.db.sha256' \
    -o -name 'etcd-backup-*.db.metadata' \
  \) \
  -mtime +"$RETENTION_DAYS" \
  -print \
  -delete

echo "Retention policy: ${RETENTION_DAYS} days"

echo
echo "===== BACKUP SUMMARY ====="

echo "Backup file: $BACKUP_FILE"
echo "Revision: ${SNAPSHOT_REVISION:-unknown}"
echo "Hash: ${SNAPSHOT_HASH:-unknown}"
echo "Keys: ${SNAPSHOT_KEYS:-unknown}"

echo
echo "=================================================="
echo " ETCD BACKUP COMPLETE"
echo "=================================================="
