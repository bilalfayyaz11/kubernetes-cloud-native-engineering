#!/bin/bash
set -euo pipefail

TARGET="${1:-.}"

echo "=================================================="
echo " KUBERNETES API COMPATIBILITY CHECK"
echo "=================================================="
echo "Target: $TARGET"

FAILED=0

scan_pattern() {
    local pattern="$1"
    local description="$2"

    echo
    echo "Checking: $description"

    if grep -RniE \
      "$pattern" \
      "$TARGET" \
      --include='*.yaml' \
      --include='*.yml' \
      --exclude-dir='.git'
    then
        echo "FAIL: $description detected."
        FAILED=1
    else
        echo "PASS: $description not detected."
    fi
}

scan_pattern \
  'apiVersion:[[:space:]]*extensions/v1beta1' \
  'removed extensions/v1beta1 API'

scan_pattern \
  'apiVersion:[[:space:]]*policy/v1beta1' \
  'removed policy/v1beta1 API'

scan_pattern \
  'apiVersion:[[:space:]]*apps/v1beta1' \
  'removed apps/v1beta1 API'

scan_pattern \
  'apiVersion:[[:space:]]*apps/v1beta2' \
  'removed apps/v1beta2 API'

scan_pattern \
  'apiVersion:[[:space:]]*networking.k8s.io/v1beta1' \
  'removed networking.k8s.io/v1beta1 API'

echo
echo "===== API VERSION INVENTORY ====="

grep -RhiE \
  '^[[:space:]]*apiVersion:' \
  "$TARGET" \
  --include='*.yaml' \
  --include='*.yml' \
  --exclude-dir='.git' \
  | sed 's/^[[:space:]]*//' \
  | sort \
  | uniq -c \
  || true

echo
if [ "$FAILED" -ne 0 ]; then
    echo "RESULT: FAILED"
    echo "Removed/deprecated API references require migration."
    exit 1
fi

echo "RESULT: PASSED"
echo "No configured removed API references detected."
