#!/usr/bin/env bash

set +e

FRONTEND_POD="$(
  kubectl get pods \
    -n frontend \
    -l app=frontend \
    -o jsonpath='{.items[0].metadata.name}'
)"

BACKEND_POD="$(
  kubectl get pods \
    -n backend \
    -l app=backend \
    -o jsonpath='{.items[0].metadata.name}'
)"

BACKEND_SERVICE_IP="$(
  kubectl get service backend-service \
    -n backend \
    -o jsonpath='{.spec.clusterIP}'
)"

DATABASE_SERVICE_IP="$(
  kubectl get service database-service \
    -n database \
    -o jsonpath='{.spec.clusterIP}'
)"

echo "========================================"
echo " NETWORKPOLICY VALIDATION"
echo "========================================"

PASS_COUNT=0

echo
echo "1. Frontend -> Backend"
echo "Expected: ALLOWED"

kubectl exec \
  -n frontend \
  "$FRONTEND_POD" \
  -- nc -zvw3 "$BACKEND_SERVICE_IP" 80 \
  >/dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "RESULT: SUCCESS (expected)"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAILED (unexpected)"
fi

echo
echo "2. Frontend -> Database"
echo "Expected: BLOCKED"

kubectl exec \
  -n frontend \
  "$FRONTEND_POD" \
  -- nc -zvw3 "$DATABASE_SERVICE_IP" 5432 \
  >/dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "RESULT: BLOCKED (expected)"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: SUCCESS (unexpected)"
fi

echo
echo "3. Backend -> Database"
echo "Expected: ALLOWED"

kubectl exec \
  -n backend \
  "$BACKEND_POD" \
  -- nc -zvw3 "$DATABASE_SERVICE_IP" 5432 \
  >/dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "RESULT: SUCCESS (expected)"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "RESULT: FAILED (unexpected)"
fi

echo
echo "Passed checks: $PASS_COUNT/3"

if [ "$PASS_COUNT" -eq 3 ]; then
  echo "PASS: NetworkPolicy behavior matches intended tier isolation"
else
  echo "FAIL: one or more policy checks did not match expectations"
fi
