#!/usr/bin/env bash

set -u

KB_FILE="${1:-}"
POLARIS_FILE="${2:-}"

OUT_DIR="$HOME/kubernetes-compliance-automation/reports"
OUT_FILE="$OUT_DIR/unified-report.txt"

mkdir -p "$OUT_DIR"

if [ ! -r "$KB_FILE" ]; then
  echo "ERROR: kube-bench report unreadable: $KB_FILE"
  exit 2
fi

if [ ! -r "$POLARIS_FILE" ]; then
  echo "ERROR: Polaris report unreadable: $POLARIS_FILE"
  exit 2
fi

if ! jq empty "$KB_FILE" >/dev/null 2>&1; then
  echo "ERROR: kube-bench report is invalid JSON"
  exit 2
fi

if ! jq empty "$POLARIS_FILE" >/dev/null 2>&1; then
  echo "ERROR: Polaris report is invalid JSON"
  exit 2
fi

CONTEXT=$(
  kubectl config current-context \
    2>/dev/null \
  || echo "unknown"
)

TIMESTAMP=$(date -Is)

KB_PASS=$(
  jq '
    if .Totals then
      (.Totals.total_pass // 0)
    else
      [
        .Controls[]?.tests[]?.results[]?
        | select(.status == "PASS")
      ]
      | length
    end
  ' "$KB_FILE"
)

KB_FAIL=$(
  jq '
    if .Totals then
      (.Totals.total_fail // 0)
    else
      [
        .Controls[]?.tests[]?.results[]?
        | select(.status == "FAIL")
      ]
      | length
    end
  ' "$KB_FILE"
)

KB_WARN=$(
  jq '
    if .Totals then
      (.Totals.total_warn // 0)
    else
      [
        .Controls[]?.tests[]?.results[]?
        | select(.status == "WARN")
      ]
      | length
    end
  ' "$KB_FILE"
)

POLARIS_SCORE=$(
  jq -r '
    .Score
    // .score
    // 0
  ' "$POLARIS_FILE"
)

POLARIS_DANGER=$(
  jq '
    [
      .Results[]?
      | .PodResult.Results[]?
      | select(
          (.Success == false)
          and
          (
            (.Severity // .severity // "") == "danger"
            or
            (.Category // .category // "") == "danger"
          )
        )
    ]
    | length
  ' "$POLARIS_FILE" 2>/dev/null
)

POLARIS_WARNING=$(
  jq '
    [
      .Results[]?
      | .PodResult.Results[]?
      | select(
          (.Success == false)
          and
          (
            (.Severity // .severity // "") == "warning"
            or
            (.Category // .category // "") == "warning"
          )
        )
    ]
    | length
  ' "$POLARIS_FILE" 2>/dev/null
)

[ -n "$POLARIS_DANGER" ] || POLARIS_DANGER=0
[ -n "$POLARIS_WARNING" ] || POLARIS_WARNING=0

DENOM=$((KB_PASS + KB_FAIL))

if [ "$DENOM" -gt 0 ]; then

  UNIFIED_SCORE=$(
    awk \
      -v kp="$KB_PASS" \
      -v kf="$KB_FAIL" \
      -v ps="$POLARIS_SCORE" \
      'BEGIN {
        score = ((kp / (kp + kf)) * 0.6) + ((ps / 100) * 0.4)
        printf "%.2f", score * 100
      }'
  )

else

  UNIFIED_SCORE=$(
    awk \
      -v ps="$POLARIS_SCORE" \
      'BEGIN {
        printf "%.2f", (ps / 100) * 40
      }'
  )

fi

if [ "$KB_FAIL" -gt 0 ]; then
  EXIT_CODE=2
  EXIT_REASON="critical kube-bench failures present"
elif [ "$KB_WARN" -gt 0 ] || \
     [ "$POLARIS_DANGER" -gt 0 ] || \
     [ "$POLARIS_WARNING" -gt 0 ] || \
     awk -v score="$POLARIS_SCORE" 'BEGIN { exit !(score < 100) }'
then
  EXIT_CODE=1
  EXIT_REASON="warnings or best-practice findings present, but no kube-bench FAIL"
else
  EXIT_CODE=0
  EXIT_REASON="fully compliant under the scoring contract"
fi

{
  echo "CLUSTER COMPLIANCE REPORT"
  echo "============================================================"
  echo "timestamp: $TIMESTAMP"
  echo "context: $CONTEXT"

  echo
  echo "KUBE-BENCH (CIS Benchmark)"
  echo "============================================================"
  echo "total_pass: $KB_PASS"
  echo "total_fail: $KB_FAIL"
  echo "total_warn: $KB_WARN"

  echo
  echo "FAIL checks:"

  FAIL_LINES=$(
    jq -r '
      .Controls[]?
      | .tests[]?
      | .results[]?
      | select(.status == "FAIL")
      | "- " +
        (.test_number // .id // "unknown") +
        " | " +
        (.test_desc // .desc // "no description")
    ' "$KB_FILE"
  )

  if [ -n "$FAIL_LINES" ]; then
    echo "$FAIL_LINES"
  else
    echo "- none"
  fi

  echo
  echo "POLARIS (Best Practices)"
  echo "============================================================"
  echo "score: $POLARIS_SCORE"
  echo "danger_count: $POLARIS_DANGER"
  echo "warning_count: $POLARIS_WARNING"

  echo
  echo "Danger-level findings:"

  DANGER_LINES=$(
    jq -r '
      .Results[]?
      | . as $resource
      | .PodResult.Results[]?
      | select(
          (.Success == false)
          and
          (
            (.Severity // .severity // "") == "danger"
            or
            (.Category // .category // "") == "danger"
          )
        )
      | "- " +
        (.ID // .id // .Name // "unknown") +
        " | resource=" +
        ($resource.Name // $resource.name // "unknown")
    ' "$POLARIS_FILE" 2>/dev/null
  )

  if [ -n "$DANGER_LINES" ]; then
    echo "$DANGER_LINES"
  else
    echo "- none or schema does not expose danger classification"
  fi

  echo
  echo "UNIFIED RISK SCORE"
  echo "============================================================"
  echo "formula:"
  echo "(kube_pass / (kube_pass + kube_fail)) * 0.6"
  echo "+ (polaris_score / 100) * 0.4"
  echo
  echo "result: ${UNIFIED_SCORE}%"

  echo
  echo "EXIT DECISION"
  echo "============================================================"
  echo "exit_code: $EXIT_CODE"
  echo "reason: $EXIT_REASON"

} | tee "$OUT_FILE"

exit "$EXIT_CODE"
