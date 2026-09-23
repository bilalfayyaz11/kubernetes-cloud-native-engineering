#!/usr/bin/env bash

set +e

NAMESPACE="network-test"

POD1_IP="$(
  kubectl get pod test-pod-1 \
    -n "$NAMESPACE" \
    -o jsonpath='{.status.podIP}'
)"

POD2_IP="$(
  kubectl get pod test-pod-2 \
    -n "$NAMESPACE" \
    -o jsonpath='{.status.podIP}'
)"

echo "========================================"
echo " CROSS-NODE POD CONNECTIVITY TEST"
echo "========================================"

echo "test-pod-1 IP: $POD1_IP"
echo "test-pod-2 IP: $POD2_IP"

echo
echo "===== test-pod-1 -> test-pod-2 ====="

kubectl exec \
  -n "$NAMESPACE" \
  test-pod-1 \
  -- ping -c 3 "$POD2_IP"

RC1=$?

echo
echo "===== test-pod-2 -> test-pod-1 ====="

kubectl exec \
  -n "$NAMESPACE" \
  test-pod-2 \
  -- ping -c 3 "$POD1_IP"

RC2=$?

echo

if [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ]; then
  echo "PASS: bidirectional Pod-to-Pod connectivity verified"
else
  echo "FAIL: one or both cross-node connectivity tests failed"
fi
