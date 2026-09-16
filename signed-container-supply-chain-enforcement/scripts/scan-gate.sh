#!/usr/bin/env bash
set -uo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <image-ref>"
  exit 1
fi

IMAGE_REF="$1"

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." \
  && pwd
)"

REPORT_DIR="${ROOT_DIR}/reports"
mkdir -p "$REPORT_DIR"

SAFE_NAME="$(
  printf '%s' "$IMAGE_REF" \
  | sed 's#[/:@]#_#g'
)"

REPORT_FILE="${REPORT_DIR}/${SAFE_NAME}.json"

echo "Scanning: $IMAGE_REF"
echo "Report:   $REPORT_FILE"

trivy image \
  --format json \
  --output "$REPORT_FILE" \
  --severity HIGH,CRITICAL \
  "$IMAGE_REF"

TRIVY_EXIT=$?

if [ "$TRIVY_EXIT" -ne 0 ]; then
  echo "FAIL: Trivy scan itself failed"
  exit 1
fi

VULN_COUNT="$(
  jq '
    [
      .Results[]?
      | .Vulnerabilities[]?
      | select(
          .Severity == "HIGH"
          or
          .Severity == "CRITICAL"
        )
    ]
    | length
  ' "$REPORT_FILE"
)"

echo "HIGH + CRITICAL vulnerabilities: $VULN_COUNT"

if [ "$VULN_COUNT" -gt 0 ]; then
  echo "FAIL: image rejected by vulnerability gate"
  exit 1
fi

echo "PASS: image approved by vulnerability gate"
exit 0
