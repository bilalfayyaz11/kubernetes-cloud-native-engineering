#!/usr/bin/env bash

set -u

AUDIT_FILE="${1:-reports/rbac-audit-events.jsonl}"

if [ ! -f "$AUDIT_FILE" ]; then
  echo "ERROR: file not found: $AUDIT_FILE"
  exit 1
fi

echo "===== RBAC SECURITY EVENT ANALYSIS ====="

echo
echo "Authentication failures (401):"

jq -r '
  select((.responseStatus.code // 0) == 401)
  |
  [
    .stageTimestamp,
    (.user.username // "-"),
    .verb,
    (.requestURI // "-")
  ]
  | @tsv
' "$AUDIT_FILE" \
  | tail -10

echo
echo "Authorization failures (403):"

jq -r '
  select((.responseStatus.code // 0) == 403)
  |
  [
    .stageTimestamp,
    (.user.username // "-"),
    .verb,
    (.objectRef.resource // "-"),
    (.objectRef.namespace // "-"),
    (.objectRef.name // "-")
  ]
  | @tsv
' "$AUDIT_FILE" \
  | tail -20

echo
echo "Top identities:"

jq -r \
  '.user.username // "unknown"' \
  "$AUDIT_FILE" \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -10

echo
echo "Top response codes:"

jq -r \
  '.responseStatus.code // 0' \
  "$AUDIT_FILE" \
  | sort \
  | uniq -c \
  | sort -nr
