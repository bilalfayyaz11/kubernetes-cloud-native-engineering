#!/usr/bin/env bash

set -u

AUDIT_FILE="${1:-reports/final-api-audit.jsonl}"

if [ ! -f "$AUDIT_FILE" ]; then
  echo "ERROR: audit file not found"
  exit 1
fi

echo "===== KUBERNETES API SECURITY ANALYSIS ====="

echo
echo "Total events:"
wc -l < "$AUDIT_FILE"

echo
echo "Authentication failures:"
jq -r '
  select((.responseStatus.code // 0) == 401)
  | .auditID
' "$AUDIT_FILE" \
  | wc -l

echo
echo "Authorization failures:"
jq -r '
  select((.responseStatus.code // 0) == 403)
  | .auditID
' "$AUDIT_FILE" \
  | wc -l

echo
echo "Top users:"
jq -r \
  '.user.username // "unknown"' \
  "$AUDIT_FILE" \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -10

echo
echo "Top API resources:"
jq -r \
  '.objectRef.resource // "non-resource"' \
  "$AUDIT_FILE" \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -15

echo
echo "Top verbs:"
jq -r \
  '.verb // "unknown"' \
  "$AUDIT_FILE" \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -10

echo
echo "Denied limited-user operations:"
jq -r '
  select(
    (.user.username // "") ==
      "system:serviceaccount:security-test:limited-user"
    and
    (.responseStatus.code // 0) == 403
  )
  |
  [
    .stageTimestamp,
    .verb,
    (.objectRef.resource // "-"),
    (.objectRef.namespace // "-")
  ]
  | @tsv
' "$AUDIT_FILE"
