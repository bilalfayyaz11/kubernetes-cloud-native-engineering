#!/usr/bin/env bash
set +e

ITERATIONS="${1:-4}"
INTERVAL="${2:-10}"

echo "=== Kubernetes Resource Monitor ==="
echo "Started: $(date)"
echo "Iterations: $ITERATIONS"
echo "Interval: ${INTERVAL}s"

for i in $(seq 1 "$ITERATIONS"); do

  echo
  echo "=============================================="
  echo "Sample $i/$ITERATIONS - $(date)"
  echo "=============================================="

  echo
  echo "--- Node Resources ---"
  kubectl top nodes 2>/dev/null || echo "Metrics unavailable"

  echo
  echo "--- Top Pods by CPU ---"
  kubectl top pods \
    -A \
    --sort-by=cpu \
    2>/dev/null \
    | head -10 || true

  echo
  echo "--- Top Pods by Memory ---"
  kubectl top pods \
    -A \
    --sort-by=memory \
    2>/dev/null \
    | head -10 || true

  if [ "$i" -lt "$ITERATIONS" ]; then
    sleep "$INTERVAL"
  fi

done

echo
echo "Monitoring finished: $(date)"
