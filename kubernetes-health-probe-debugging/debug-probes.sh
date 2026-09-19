#!/usr/bin/env bash
set -euo pipefail

POD_NAME="${1:-}"
NAMESPACE="${2:-default}"

if [ -z "$POD_NAME" ]; then
    echo "Usage: $0 <pod-name> [namespace]"
    exit 1
fi

if ! kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" >/dev/null 2>&1
then
    echo "ERROR: Pod '$POD_NAME' not found in namespace '$NAMESPACE'."
    exit 1
fi

echo "=================================================="
echo " KUBERNETES PROBE DEBUG REPORT"
echo "=================================================="
echo "Pod       : $POD_NAME"
echo "Namespace : $NAMESPACE"
echo

echo "===== 1. POD STATUS ====="
kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" \
  -o wide

echo
echo "===== 2. CONDITIONS ====="
kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" \
  -o json | jq '.status.conditions'

echo
echo "===== 3. CONTAINER STATUS ====="
kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" \
  -o json | jq '.status.containerStatuses'

echo
echo "===== 4. PROBE CONFIGURATION ====="
kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" \
  -o json | jq '
    .spec.containers[] |
    {
      container: .name,
      startupProbe: .startupProbe,
      readinessProbe: .readinessProbe,
      livenessProbe: .livenessProbe
    }
  '

echo
echo "===== 5. RECENT EVENTS ====="
kubectl get events \
  -n "$NAMESPACE" \
  --field-selector involvedObject.name="$POD_NAME" \
  --sort-by='.lastTimestamp' | \
  tail -n 20

echo
echo "===== 6. CURRENT LOGS ====="
for container in $(kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" \
  -o jsonpath='{.spec.containers[*].name}')
do
    echo
    echo "--- Container: $container ---"

    kubectl logs "$POD_NAME" \
      -n "$NAMESPACE" \
      -c "$container" \
      --tail=30 || true
done

echo
echo "===== 7. PREVIOUS CONTAINER LOGS ====="
for container in $(kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" \
  -o jsonpath='{.spec.containers[*].name}')
do
    echo
    echo "--- Previous: $container ---"

    kubectl logs "$POD_NAME" \
      -n "$NAMESPACE" \
      -c "$container" \
      --previous \
      --tail=30 2>/dev/null || \
      echo "No previous container logs available."
done

echo
echo "===== 8. RESTART SUMMARY ====="
kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" \
  -o json | jq '
    .status.containerStatuses[] |
    {
      container: .name,
      ready: .ready,
      restartCount: .restartCount,
      state: .state,
      lastState: .lastState
    }
  '

echo
echo "=================================================="
echo " DEBUG REPORT COMPLETE"
echo "=================================================="
