#!/usr/bin/env bash

set -u

PKI_DIR="${PKI_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pki}"
WARN_DAYS=30

usage() {
  cat <<USAGE
Usage:
  $0 [--warn-days N]

Arguments:
  --warn-days N   Emit WARNING when a certificate expires within N days.
                  Default: 30
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --warn-days)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --warn-days requires a numeric argument" >&2
        exit 1
      fi

      WARN_DAYS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "$WARN_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --warn-days must be a non-negative integer" >&2
  exit 1
fi

CERTIFICATES=(
  "root-ca/ca.pem"
  "intermediate-ca/ca.pem"
  "api-server/api-server.pem"
  "etcd/etcd.pem"
  "kubelet/kubelet.pem"
  "certs/admin.pem"
)

NOW_EPOCH="$(date +%s)"
HAS_EXPIRED=0
HAS_WARNING=0

for relative_path in "${CERTIFICATES[@]}"; do
  cert="${PKI_DIR}/${relative_path}"

  if [ ! -f "$cert" ]; then
    echo "EXPIRED ${relative_path}  certificate missing (unknown date)"
    HAS_EXPIRED=1
    continue
  fi

  end_date="$(
    openssl x509 \
      -in "$cert" \
      -noout \
      -enddate \
      2>/dev/null \
      | cut -d= -f2-
  )"

  if [ -z "$end_date" ]; then
    echo "EXPIRED ${relative_path}  unreadable certificate (unknown date)"
    HAS_EXPIRED=1
    continue
  fi

  END_EPOCH="$(date -u -d "$end_date" +%s 2>/dev/null)"

  if [ -z "$END_EPOCH" ]; then
    echo "EXPIRED ${relative_path}  invalid expiry date (unknown date)"
    HAS_EXPIRED=1
    continue
  fi

  ISO_DATE="$(
    date \
      -u \
      -d "@${END_EPOCH}" \
      '+%Y-%m-%dT%H:%M:%SZ'
  )"

  DIFF_SECONDS=$(( END_EPOCH - NOW_EPOCH ))

  if [ "$DIFF_SECONDS" -lt 0 ]; then
    DAYS_AGO=$(( (-DIFF_SECONDS + 86399) / 86400 ))

    printf 'EXPIRED %-40s expired %d days ago (%s)\n' \
      "$relative_path" \
      "$DAYS_AGO" \
      "$ISO_DATE"

    HAS_EXPIRED=1
  else
    DAYS_LEFT=$(( DIFF_SECONDS / 86400 ))

    if [ "$DAYS_LEFT" -le "$WARN_DAYS" ]; then
      printf 'WARNING %-40s expires in %d days  (%s)\n' \
        "$relative_path" \
        "$DAYS_LEFT" \
        "$ISO_DATE"

      HAS_WARNING=1
    else
      printf 'OK      %-40s expires in %d days  (%s)\n' \
        "$relative_path" \
        "$DAYS_LEFT" \
        "$ISO_DATE"
    fi
  fi
done

if [ "$HAS_EXPIRED" -eq 1 ]; then
  exit 1
fi

if [ "$HAS_WARNING" -eq 1 ]; then
  exit 2
fi

exit 0
