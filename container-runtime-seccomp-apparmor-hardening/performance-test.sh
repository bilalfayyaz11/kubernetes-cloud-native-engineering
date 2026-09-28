#!/bin/bash
set +e

echo "=================================================="
echo " SECURITY HARDENING PERFORMANCE ASSESSMENT"
echo "=================================================="

echo
echo "===== CLEAN OLD REGULAR PERFORMANCE POD ====="
kubectl delete pod perf-test-regular \
  --ignore-not-found=true \
  --wait=true >/dev/null 2>&1

echo
echo "===== CREATE REGULAR PERFORMANCE POD ====="

kubectl run perf-test-regular \
  --image=alpine:3.20 \
  --restart=Never \
  --command -- sh -c 'while true; do sleep 30; done'

kubectl wait \
  --for=condition=Ready \
  pod/perf-test-regular \
  --timeout=120s

echo
echo "===== REGULAR POD FILESYSTEM TEST ====="

REGULAR_START=$(date +%s%N)

kubectl exec perf-test-regular -- sh -c '
find /usr/bin -maxdepth 1 -type f 2>/dev/null | wc -l
' >/tmp/regular-perf.txt 2>/dev/null

REGULAR_END=$(date +%s%N)

REGULAR_MS=$(( (REGULAR_END - REGULAR_START) / 1000000 ))

cat /tmp/regular-perf.txt
echo "Regular Pod elapsed time: ${REGULAR_MS} ms"

echo
echo "===== HARDENED POD FILESYSTEM TEST ====="

HARDENED_START=$(date +%s%N)

kubectl exec hardened-test-pod -- sh -c '
find /usr/bin -maxdepth 1 -type f 2>/dev/null | wc -l
' >/tmp/hardened-perf.txt 2>/dev/null

HARDENED_RC=$?

HARDENED_END=$(date +%s%N)

HARDENED_MS=$(( (HARDENED_END - HARDENED_START) / 1000000 ))

if [ "$HARDENED_RC" -eq 0 ]; then
  cat /tmp/hardened-perf.txt
  echo "Hardened Pod elapsed time: ${HARDENED_MS} ms"
else
  echo "Hardened command restricted by security controls"
fi

echo
echo "===== TIMING SUMMARY ====="
echo "Regular Pod  : ${REGULAR_MS} ms"

if [ "$HARDENED_RC" -eq 0 ]; then
  echo "Hardened Pod : ${HARDENED_MS} ms"
else
  echo "Hardened Pod : command restricted"
fi

echo
echo "===== METRICS SERVER CHECK ====="

kubectl top pods 2>/dev/null \
  || echo "Metrics Server unavailable; live CPU/memory comparison skipped"

echo
echo "===== CLEAN PERFORMANCE POD ====="

kubectl delete pod perf-test-regular \
  --ignore-not-found=true \
  --wait=true

rm -f /tmp/regular-perf.txt /tmp/hardened-perf.txt

echo
echo "=================================================="
echo " PERFORMANCE ASSESSMENT COMPLETE"
echo "=================================================="
