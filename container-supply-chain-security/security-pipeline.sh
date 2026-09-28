#!/bin/bash
set +e

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <immutable-image-reference> <public-key> [analysis-source]"
  exit 2
fi

IMAGE="$1"
PUBLIC_KEY="$2"
ANALYSIS_SOURCE="${3:-$IMAGE}"

SAFE_NAME="$(
  echo "$IMAGE" \
  | sed 's#[/:@]#_#g'
)"

SBOM_FILE="${SAFE_NAME}-sbom.spdx.json"
VULN_FILE="${SAFE_NAME}-vuln.json"
REPORT_FILE="${SAFE_NAME}-security-report.md"

MAX_CRITICAL=0
MAX_HIGH=5

echo "=================================================="
echo " SUPPLY CHAIN SECURITY PIPELINE"
echo "=================================================="

echo
echo "Policy image reference:"
echo "$IMAGE"

echo
echo "Analysis source:"
echo "$ANALYSIS_SOURCE"

echo
echo "===== STEP 1 — IMMUTABLE REFERENCE CHECK ====="

if echo "$IMAGE" | grep -q '@sha256:'; then
  IMMUTABLE=true
  echo "PASS: immutable digest reference detected"
else
  IMMUTABLE=false
  echo "FAIL: mutable/tag-only reference detected"
fi

echo
echo "===== STEP 2 — SBOM GENERATION ====="

if echo "$ANALYSIS_SOURCE" | grep -q '^docker:'; then

  sudo syft \
    "$ANALYSIS_SOURCE" \
    -o spdx-json \
    > "$SBOM_FILE"

else

  syft \
    "$ANALYSIS_SOURCE" \
    -o spdx-json \
    > "$SBOM_FILE"
fi

SBOM_RC=$?

if [ "$SBOM_RC" -eq 0 ] && \
   [ -s "$SBOM_FILE" ] && \
   jq empty "$SBOM_FILE" >/dev/null 2>&1; then

  SBOM_OK=true
  SBOM_PACKAGES="$(
    jq '[.packages[]?] | length' "$SBOM_FILE"
  )"

  echo "PASS: SBOM generated"
  echo "Packages: $SBOM_PACKAGES"

else

  SBOM_OK=false
  SBOM_PACKAGES=0
  echo "FAIL: SBOM generation failed"
fi

echo
echo "===== STEP 3 — VULNERABILITY SCAN ====="

TRIVY_TARGET="$ANALYSIS_SOURCE"

if echo "$TRIVY_TARGET" | grep -q '^docker:'; then
  TRIVY_TARGET="${TRIVY_TARGET#docker:}"
fi

trivy image \
  --scanners vuln \
  --format json \
  --output "$VULN_FILE" \
  "$TRIVY_TARGET"

TRIVY_RC=$?

if [ "$TRIVY_RC" -eq 0 ] && \
   [ -s "$VULN_FILE" ] && \
   jq empty "$VULN_FILE" >/dev/null 2>&1; then

  VULN_SCAN_OK=true

else

  VULN_SCAN_OK=false
fi

CRITICAL="$(
  jq '
    [
      .Results[]?.Vulnerabilities[]?
      | select(.Severity == "CRITICAL")
    ]
    | length
  ' "$VULN_FILE" 2>/dev/null
)"

HIGH="$(
  jq '
    [
      .Results[]?.Vulnerabilities[]?
      | select(.Severity == "HIGH")
    ]
    | length
  ' "$VULN_FILE" 2>/dev/null
)"

CRITICAL="${CRITICAL:-0}"
HIGH="${HIGH:-0}"

echo "Critical: $CRITICAL"
echo "High    : $HIGH"

if [ "$VULN_SCAN_OK" = true ] && \
   [ "$CRITICAL" -le "$MAX_CRITICAL" ] && \
   [ "$HIGH" -le "$MAX_HIGH" ]; then

  VULN_GATE=true
  echo "PASS: vulnerability threshold satisfied"

else

  VULN_GATE=false
  echo "BLOCK: vulnerability threshold exceeded"
fi

echo
echo "===== STEP 4 — COSIGN SIGNATURE VERIFICATION ====="

COSIGN_ARGS=(
  verify
  --key "$PUBLIC_KEY"
)

if echo "$IMAGE" \
  | grep -Eq '^(127\.0\.0\.1|localhost):5001/'; then

  COSIGN_ARGS+=(--allow-insecure-registry)
fi

COSIGN_ARGS+=("$IMAGE")

cosign "${COSIGN_ARGS[@]}" \
  >/tmp/cosign-pipeline-output.json \
  2>/tmp/cosign-pipeline-error.txt

COSIGN_RC=$?

if [ "$COSIGN_RC" -eq 0 ]; then

  SIGNED=true
  echo "PASS: valid Cosign signature"

else

  SIGNED=false
  echo "FAIL: signature missing or invalid"
fi

echo
echo "===== STEP 5 — POLICY DECISION ====="

if [ "$IMMUTABLE" = true ] && \
   [ "$SBOM_OK" = true ] && \
   [ "$VULN_SCAN_OK" = true ] && \
   [ "$VULN_GATE" = true ] && \
   [ "$SIGNED" = true ]; then

  DECISION="ALLOW"

else

  DECISION="BLOCK"
fi

echo
echo "Decision: $DECISION"

echo
echo "===== STEP 6 — GENERATE SECURITY REPORT ====="

cat > "$REPORT_FILE" <<EOR
# Supply Chain Security Report

## Artifact

Policy reference:

\`$IMAGE\`

Analysis source:

\`$ANALYSIS_SOURCE\`

## Control Results

| Control | Result |
|---|---|
| Immutable digest | $IMMUTABLE |
| SBOM generated | $SBOM_OK |
| SBOM package count | $SBOM_PACKAGES |
| Vulnerability scan | $VULN_SCAN_OK |
| Critical vulnerabilities | $CRITICAL |
| High vulnerabilities | $HIGH |
| Vulnerability policy passed | $VULN_GATE |
| Cosign signature verified | $SIGNED |

## Security Threshold

- Maximum CRITICAL: $MAX_CRITICAL
- Maximum HIGH: $MAX_HIGH

## Final Decision

**$DECISION**

## Interpretation

A cryptographically signed artifact can still be blocked when its
vulnerability posture violates policy.

Image signing proves authenticity and integrity.

Vulnerability scanning evaluates known security weaknesses.

Both controls must succeed independently before an artifact receives
an ALLOW decision.
EOR

rm -f \
  /tmp/cosign-pipeline-output.json \
  /tmp/cosign-pipeline-error.txt

echo "Report: $REPORT_FILE"

echo
echo "=================================================="
echo " PIPELINE COMPLETE — $DECISION"
echo "=================================================="

if [ "$DECISION" = "ALLOW" ]; then
  exit 0
else
  exit 1
fi
