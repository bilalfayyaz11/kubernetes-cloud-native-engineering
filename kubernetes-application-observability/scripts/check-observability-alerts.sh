#!/usr/bin/env bash
set +e

ALERTS=0

echo "=== Kubernetes Observability Alert Check ==="
echo "Timestamp: $(date)"
echo

FAIL_READY="$(kubectl get pod failing-webapp \
  -o jsonpath='{.status.containerStatuses[0].ready}' \
  2>/dev/null)"

FAIL_RESTARTS="$(kubectl get pod failing-webapp \
  -o jsonpath='{.status.containerStatuses[0].restartCount}' \
  2>/dev/null)"

if [ "$FAIL_READY" = "false" ]; then
  echo "ALERT: failing-webapp is not Ready"
  ALERTS=$((ALERTS+1))
fi

if [ "${FAIL_RESTARTS:-0}" -gt 0 ] 2>/dev/null; then
  echo "ALERT: failing-webapp has restarted ${FAIL_RESTARTS} time(s)"
  ALERTS=$((ALERTS+1))
fi

PROBLEM_STATE="$(kubectl get pod problematic-app \
  -o jsonpath='{.status.phase}' \
  2>/dev/null)"

if [ "$PROBLEM_STATE" != "Running" ]; then
  echo "ALERT: problematic-app phase=${PROBLEM_STATE:-unknown}"
  ALERTS=$((ALERTS+1))
fi

WARNING_EVENTS="$(kubectl get events \
  -A \
  --field-selector type=Warning \
  --no-headers \
  2>/dev/null \
  | wc -l)"

echo
echo "Warning events currently visible: $WARNING_EVENTS"
echo "Observability alerts raised: $ALERTS"

exit 0
