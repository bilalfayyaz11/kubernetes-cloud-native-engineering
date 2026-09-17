#!/usr/bin/env bash

set -u

AUDIT_FILE="${1:-reports/recent-audit-events.jsonl}"

if [ ! -f "$AUDIT_FILE" ]; then
  echo "ERROR: audit file not found: $AUDIT_FILE"
  exit 1
fi

echo "===== API SERVER AUDIT SUMMARY ====="

echo
echo "Total events:"
wc -l < "$AUDIT_FILE"

echo
echo "Response codes:"
jq -r \
  '.responseStatus.code // 0' \
  "$AUDIT_FILE" \
  2>/dev/null \
  | sort \
  | uniq -c \
  | sort -nr

echo
echo "Top verbs:"
jq -r \
  '.verb // "unknown"' \
  "$AUDIT_FILE" \
  2>/dev/null \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -10

echo
echo "Top users:"
jq -r \
  '.user.username // "unknown"' \
  "$AUDIT_FILE" \
  2>/dev/null \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -10

echo
echo "Secret operations:"
jq -r '
  select(.objectRef.resource == "secrets")
  |
  [
    .stageTimestamp,
    .verb,
    (.objectRef.namespace // "-"),
    (.objectRef.name // "-"),
    (.user.username // "-"),
    (.responseStatus.code // 0)
  ]
  | @tsv
' "$AUDIT_FILE" \
  2>/dev/null
