#!/usr/bin/env bash

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKI_DIR="${PKI_DIR:-${BASE_DIR}/pki}"
CONFIG_DIR="${CONFIG_DIR:-${BASE_DIR}/config}"

usage() {
  cat <<USAGE
Usage:
  $0 <component>

Supported components:
  api-server
  etcd
  kubelet
  admin
USAGE
}

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 1
fi

COMPONENT="$1"

case "$COMPONENT" in
  api-server)
    CERT="${PKI_DIR}/api-server/api-server.pem"
    KEY="${PKI_DIR}/api-server/api-server-key.pem"
    CSR="${PKI_DIR}/api-server/api-server.csr"
    REQ_CONFIG="${CONFIG_DIR}/api-server.cnf"
    EXT_CONFIG="${CONFIG_DIR}/api-server-ext.cnf"
    EXT_SECTION="v3_leaf"
    ;;

  etcd)
    CERT="${PKI_DIR}/etcd/etcd.pem"
    KEY="${PKI_DIR}/etcd/etcd-key.pem"
    CSR="${PKI_DIR}/etcd/etcd.csr"
    REQ_CONFIG="${CONFIG_DIR}/etcd.cnf"
    EXT_CONFIG="${CONFIG_DIR}/etcd-ext.cnf"
    EXT_SECTION="v3_leaf"
    ;;

  kubelet)
    CERT="${PKI_DIR}/kubelet/kubelet.pem"
    KEY="${PKI_DIR}/kubelet/kubelet-key.pem"
    CSR="${PKI_DIR}/kubelet/kubelet.csr"
    REQ_CONFIG="${CONFIG_DIR}/kubelet.cnf"
    EXT_CONFIG="${CONFIG_DIR}/kubelet-ext.cnf"
    EXT_SECTION="v3_leaf"
    ;;

  admin)
    CERT="${PKI_DIR}/certs/admin.pem"
    KEY="${PKI_DIR}/keys/admin-key.pem"
    CSR="${PKI_DIR}/certs/admin.csr"
    REQ_CONFIG="${CONFIG_DIR}/admin.cnf"
    EXT_CONFIG="${CONFIG_DIR}/admin-ext.cnf"
    EXT_SECTION="v3_leaf"
    ;;

  *)
    echo "ERROR: unsupported component: $COMPONENT" >&2
    usage >&2
    exit 1
    ;;
esac

CA_CERT="${PKI_DIR}/intermediate-ca/ca.pem"
CA_KEY="${PKI_DIR}/intermediate-ca/ca-key.pem"
CA_CHAIN="${PKI_DIR}/intermediate-ca/ca-chain.pem"

NEW_CERT="${CERT}.new"
NEW_KEY="${KEY}.new"
NEW_CSR="${CSR}.new"

TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
ARCHIVE_DIR="${PKI_DIR}/archive/${COMPONENT}/${TIMESTAMP}"

cleanup_new() {
  rm -f \
    "$NEW_CERT" \
    "$NEW_KEY" \
    "$NEW_CSR"
}

rollback() {
  echo "ERROR: rotation validation failed; restoring archived credential" >&2

  if [ -f "${ARCHIVE_DIR}/$(basename "$CERT")" ]; then
    cp \
      "${ARCHIVE_DIR}/$(basename "$CERT")" \
      "$CERT"
  fi

  if [ -f "${ARCHIVE_DIR}/$(basename "$KEY")" ]; then
    cp \
      "${ARCHIVE_DIR}/$(basename "$KEY")" \
      "$KEY"

    chmod 0400 \
      "$KEY"
  fi

  cleanup_new
}

for required in \
  "$CERT" \
  "$KEY" \
  "$REQ_CONFIG" \
  "$EXT_CONFIG" \
  "$CA_CERT" \
  "$CA_KEY" \
  "$CA_CHAIN"
do
  if [ ! -f "$required" ]; then
    echo "ERROR: required file missing: $required" >&2
    exit 1
  fi
done

cleanup_new

echo "Generating replacement key..."

if ! openssl genrsa \
  -out "$NEW_KEY" \
  2048
then
  cleanup_new
  exit 1
fi

chmod 0400 \
  "$NEW_KEY"

echo "Generating replacement CSR..."

if ! openssl req \
  -new \
  -sha256 \
  -key "$NEW_KEY" \
  -out "$NEW_CSR" \
  -config "$REQ_CONFIG"
then
  cleanup_new
  exit 1
fi

echo "Signing replacement certificate..."

if ! openssl x509 \
  -req \
  -sha256 \
  -days 365 \
  -in "$NEW_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$NEW_CERT" \
  -extfile "$EXT_CONFIG" \
  -extensions "$EXT_SECTION"
then
  cleanup_new
  exit 1
fi

chmod 0444 \
  "$NEW_CERT"

echo "Verifying replacement certificate..."

if ! openssl verify \
  -CAfile "$CA_CHAIN" \
  "$NEW_CERT"
then
  echo "ERROR: new certificate failed chain verification" >&2
  cleanup_new
  exit 1
fi

NEW_CERT_HASH="$(
  openssl x509 \
    -in "$NEW_CERT" \
    -pubkey \
    -noout \
  | openssl pkey \
      -pubin \
      -outform DER \
      2>/dev/null \
  | sha256sum \
  | awk '{print $1}'
)"

NEW_KEY_HASH="$(
  openssl pkey \
    -in "$NEW_KEY" \
    -pubout \
    -outform DER \
    2>/dev/null \
  | sha256sum \
  | awk '{print $1}'
)"

if [ "$NEW_CERT_HASH" != "$NEW_KEY_HASH" ]; then
  echo "ERROR: new certificate/key pair mismatch" >&2
  cleanup_new
  exit 1
fi

echo "Creating archive..."

if ! mkdir -p \
  "$ARCHIVE_DIR"
then
  cleanup_new
  exit 1
fi

chmod 0700 \
  "$ARCHIVE_DIR"

echo "Archiving current credential..."

if ! cp \
  "$CERT" \
  "${ARCHIVE_DIR}/$(basename "$CERT")"
then
  cleanup_new
  exit 1
fi

if ! cp \
  "$KEY" \
  "${ARCHIVE_DIR}/$(basename "$KEY")"
then
  cleanup_new
  exit 1
fi

chmod 0400 \
  "${ARCHIVE_DIR}/$(basename "$KEY")"

echo "Replacing live key..."

if ! mv \
  "$NEW_KEY" \
  "$KEY"
then
  cleanup_new
  exit 1
fi

chmod 0400 \
  "$KEY"

echo "Replacing live certificate..."

if ! mv \
  "$NEW_CERT" \
  "$CERT"
then
  echo "ERROR: certificate replacement failed" >&2

  cp \
    "${ARCHIVE_DIR}/$(basename "$KEY")" \
    "$KEY"

  chmod 0400 \
    "$KEY"

  cleanup_new
  exit 1
fi

chmod 0444 \
  "$CERT"

rm -f \
  "$NEW_CSR"

echo "Validating live certificate chain..."

if ! openssl verify \
  -CAfile "$CA_CHAIN" \
  "$CERT"
then
  rollback
  exit 1
fi

LIVE_CERT_HASH="$(
  openssl x509 \
    -in "$CERT" \
    -pubkey \
    -noout \
  | openssl pkey \
      -pubin \
      -outform DER \
      2>/dev/null \
  | sha256sum \
  | awk '{print $1}'
)"

LIVE_KEY_HASH="$(
  openssl pkey \
    -in "$KEY" \
    -pubout \
    -outform DER \
    2>/dev/null \
  | sha256sum \
  | awk '{print $1}'
)"

if [ "$LIVE_CERT_HASH" != "$LIVE_KEY_HASH" ]; then
  echo "ERROR: live certificate/key pair mismatch after rotation" >&2
  rollback
  exit 1
fi

NOT_BEFORE="$(
  openssl x509 \
    -in "$CERT" \
    -noout \
    -startdate \
  | cut -d= -f2-
)"

NOT_BEFORE_EPOCH="$(
  date -u \
    -d "$NOT_BEFORE" \
    +%s \
    2>/dev/null
)"

NOW_EPOCH="$(date -u +%s)"

if [ -z "$NOT_BEFORE_EPOCH" ]; then
  echo "ERROR: unable to parse notBefore timestamp" >&2
  rollback
  exit 1
fi

AGE_SECONDS=$(( NOW_EPOCH - NOT_BEFORE_EPOCH ))

if [ "$AGE_SECONDS" -lt 0 ]; then
  FUTURE_OFFSET=$(( -AGE_SECONDS ))

  if [ "$FUTURE_OFFSET" -gt 5 ]; then
    echo "ERROR: new certificate notBefore is too far in the future" >&2
    rollback
    exit 1
  fi

  AGE_SECONDS=0
fi

if [ "$AGE_SECONDS" -gt 60 ]; then
  echo "ERROR: new certificate notBefore is older than 60 seconds" >&2
  rollback
  exit 1
fi

echo
echo "Rotation successful"
echo "Component: $COMPONENT"
echo "Certificate: $CERT"
echo "Archive: $ARCHIVE_DIR"
echo "notBefore: $NOT_BEFORE"
echo "Age: ${AGE_SECONDS}s"

exit 0
