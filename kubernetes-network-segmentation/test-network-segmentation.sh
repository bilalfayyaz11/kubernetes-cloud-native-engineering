#!/usr/bin/env bash

set +e

PRIMARY_NS="network-segmentation"
EXTERNAL_NS="external-segmentation"

BACKEND_IP="$(
  kubectl get pod backend \
    -n "$PRIMARY_NS" \
    -o jsonpath='{.status.podIP}' \
    2>/dev/null
)"

PASS_COUNT=0
FAIL_COUNT=0

result() {
  NAME="$1"
  EXPECTATION="$2"
  STATUS="$3"

  if [ "$EXPECTATION" = "ALLOW" ]; then

    if [ "$STATUS" -eq 0 ]; then
      echo "PASS | $NAME | allowed"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      echo "FAIL | $NAME | unexpectedly blocked"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

  else

    if [ "$STATUS" -ne 0 ]; then
      echo "PASS | $NAME | blocked"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      echo "FAIL | $NAME | unexpectedly allowed"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

  fi
}

echo "=== Kubernetes Network Segmentation Validation ==="
echo

kubectl exec frontend \
  -n "$PRIMARY_NS" \
  -- sh -c "nc -z -w 5 '$BACKEND_IP' 5432" \
  >/dev/null 2>&1

result "frontend -> backend:5432" "ALLOW" "$?"

kubectl exec test-client \
  -n "$PRIMARY_NS" \
  -- nc -z -w 5 "$BACKEND_IP" 5432 \
  >/dev/null 2>&1

result "test-client -> backend:5432" "BLOCK" "$?"

kubectl exec external-client \
  -n "$EXTERNAL_NS" \
  -- nc -z -w 5 "$BACKEND_IP" 5432 \
  >/dev/null 2>&1

result "external-client -> backend:5432" "BLOCK" "$?"

kubectl exec backend \
  -n "$PRIMARY_NS" \
  -- sh -c "nc -z -w 5 frontend-web 80" \
  >/dev/null 2>&1

result "backend -> frontend:80" "ALLOW" "$?"

kubectl exec backend \
  -n "$PRIMARY_NS" \
  -- sh -c "nc -z -w 5 external-web.external-segmentation.svc.cluster.local 80" \
  >/dev/null 2>&1

result "backend -> external-web:80" "BLOCK" "$?"

kubectl exec backend \
  -n "$PRIMARY_NS" \
  -- sh -c "getent hosts frontend-web.network-segmentation.svc.cluster.local >/dev/null 2>&1"

result "backend DNS resolution" "ALLOW" "$?"

echo
echo "PASS: $PASS_COUNT"
echo "FAIL: $FAIL_COUNT"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "OVERALL: PASS"
else
  echo "OVERALL: REVIEW"
fi
