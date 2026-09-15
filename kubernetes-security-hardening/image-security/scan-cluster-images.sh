#!/usr/bin/env bash

set -u

REPORT_DIR="security-reports/cluster-images"

mkdir -p "$REPORT_DIR"

kubectl get pods \
  --all-namespaces \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | sort -u \
  > security-reports/cluster-images.txt

echo "Scanning HIGH and CRITICAL vulnerabilities..."
echo

while IFS= read -r image; do

  [ -z "$image" ] && continue

  SAFE_NAME=$(printf '%s' "$image" \
    | sed 's#[/:@]#_#g')

  REPORT="${REPORT_DIR}/${SAFE_NAME}.json"

  echo "=================================================="
  echo "IMAGE: $image"
  echo "=================================================="

  trivy image \
    --severity HIGH,CRITICAL \
    --format json \
    --output "$REPORT" \
    "$image" \
    || true

  python3 - "$REPORT" <<'PY'
import json
import sys

path = sys.argv[1]

try:
    with open(path) as f:
        data = json.load(f)
except Exception as exc:
    print(f"Unable to parse report: {exc}")
    raise SystemExit(0)

high = 0
critical = 0

for result in data.get("Results") or []:
    for vuln in result.get("Vulnerabilities") or []:
        sev = vuln.get("Severity")

        if sev == "HIGH":
            high += 1
        elif sev == "CRITICAL":
            critical += 1

print(f"HIGH={high}")
print(f"CRITICAL={critical}")
print(f"TOTAL={high + critical}")
PY

  echo

done < security-reports/cluster-images.txt
