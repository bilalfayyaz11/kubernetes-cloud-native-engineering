#!/usr/bin/env bash
set +e

ETCDCTL="/usr/local/bin/etcdctl"
ETCDUTL="/usr/local/bin/etcdutl"

BACKUP_DIR="/opt/etcd-backup"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

ETCD_ENDPOINT="https://127.0.0.1:2379"
ETCD_CA="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/healthcheck-client.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/healthcheck-client.key"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"
METADATA_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.metadata.txt"

sudo mkdir -p "$BACKUP_DIR"
sudo chmod 700 "$BACKUP_DIR"

echo "=== Etcd Backup ==="
echo "Timestamp: $(date)"
echo

echo "1. Checking etcd health..."

if ! sudo env ETCDCTL_API=3 \
  "$ETCDCTL" \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CA" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  endpoint health
then
  echo "ERROR: etcd endpoint unhealthy."
  exit 1
fi

echo
echo "2. Creating snapshot..."

if ! sudo env ETCDCTL_API=3 \
  "$ETCDCTL" \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CA" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  snapshot save "$BACKUP_FILE"
then
  echo "ERROR: snapshot creation failed."
  exit 1
fi

echo
echo "3. Verifying snapshot integrity..."

if ! sudo "$ETCDUTL" snapshot status \
  "$BACKUP_FILE" \
  --write-out=table
then
  echo "ERROR: snapshot integrity check failed."
  exit 1
fi

SHA256="$(sudo sha256sum "$BACKUP_FILE" | awk '{print $1}')"
SIZE="$(sudo stat -c '%s' "$BACKUP_FILE")"

REVISION="$(sudo "$ETCDUTL" snapshot status \
  "$BACKUP_FILE" \
  --write-out=json \
  | jq -r '.revision // .Revision // empty')"

sudo tee "$METADATA_FILE" >/dev/null <<META
timestamp=$(date -Is)
snapshot=$(basename "$BACKUP_FILE")
size_bytes=$SIZE
sha256=$SHA256
revision=${REVISION:-unknown}
retention_days=$RETENTION_DAYS
classification=sensitive
repository_policy=do-not-commit-snapshot-database
META

sudo chmod 600 "$METADATA_FILE"

echo
echo "4. Applying retention policy..."

sudo find "$BACKUP_DIR" \
  -type f \
  -name 'etcd-snapshot-*.db' \
  -mtime "+${RETENTION_DAYS}" \
  -print \
  -delete

sudo find "$BACKUP_DIR" \
  -type f \
  -name 'etcd-snapshot-*.metadata.txt' \
  -mtime "+${RETENTION_DAYS}" \
  -print \
  -delete

echo
echo "5. Backup summary:"
echo "Snapshot: $(basename "$BACKUP_FILE")"
echo "Size:     $SIZE bytes"
echo "SHA256:   $SHA256"
echo "Revision: ${REVISION:-unknown}"
echo
echo "Backup completed successfully."

exit 0
