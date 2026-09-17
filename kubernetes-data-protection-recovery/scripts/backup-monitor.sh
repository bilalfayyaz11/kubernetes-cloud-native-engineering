#!/usr/bin/env bash

set -u

BACKUP_DIR="${BACKUP_DIR:-$HOME/.kubernetes-data-protection-backups}"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"

echo "===== ETCD BACKUP MONITOR ====="

if [ ! -d "$BACKUP_DIR" ]; then
  echo "FAIL: backup directory missing"
  exit 1
fi

LATEST=$(
  find "$BACKUP_DIR" \
    -maxdepth 1 \
    -type f \
    -name 'etcd-snapshot-*.db' \
    -printf '%T@ %p\n' \
  | sort -nr \
  | head -1 \
  | cut -d' ' -f2-
)

if [ -z "$LATEST" ]; then
  echo "FAIL: no etcd snapshot found"
  exit 1
fi

echo "Latest backup:"
echo "$LATEST"

echo
echo "Backup metadata:"

stat \
  --printf='size=%s bytes\nmodified=%y\n' \
  "$LATEST"

AGE_SECONDS=$(
  $(
    date +%s
  ) \
  -
  $(
    stat -c %Y "$LATEST"
  )
)

MAX_AGE_SECONDS=$(
  MAX_AGE_HOURS * 3600
)

if [ "$AGE_SECONDS" -le "$MAX_AGE_SECONDS" ]; then
  echo "PASS: backup age within ${MAX_AGE_HOURS} hours"
else
  echo "WARNING: backup older than ${MAX_AGE_HOURS} hours"
fi

if [ -f "${LATEST}.sha256" ]; then

  cd "$BACKUP_DIR"

  if sha256sum \
    -c \
    "$(basename "${LATEST}.sha256")"
  then
    echo "PASS: backup SHA-256 integrity valid"
  else
    echo "FAIL: backup SHA-256 integrity invalid"
  fi

else

  echo "FAIL: backup hash sidecar missing"

fi
