#!/usr/bin/env bash
set +e

SAMPLES="${1:-5}"
INTERVAL="${2:-10}"

echo "=================================================="
echo " Kubernetes Application Observability Monitor"
echo "=================================================="
echo "Started: $(date)"
echo "Samples: $SAMPLES"
echo "Interval: ${INTERVAL}s"

for i in $(seq 1 "$SAMPLES"); do

  echo
  echo "=================================================="
  echo " SAMPLE $i/$SAMPLES - $(date)"
  echo "=================================================="

  echo
  echo "--- Node Metrics ---"
  kubectl top nodes 2>/dev/null || echo "Metrics unavailable"

  echo
  echo "--- Top Pods by CPU ---"
  kubectl top pods \
    -A \
    --sort-by=cpu \
    2>/dev/null \
    | head -12 || true

  echo
  echo "--- Top Pods by Memory ---"
  kubectl top pods \
    -A \
    --sort-by=memory \
    2>/dev/null \
    | head -12 || true

  echo
  echo "--- Webapp Health ---"
  kubectl get pods \
    -l app=webapp \
    -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount' \
    2>/dev/null || true

  echo
  echo "--- Failing Probe Pod ---"
  kubectl get pod failing-webapp \
    -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount' \
    2>/dev/null || true

  echo
  echo "--- CPU Intensive Pod ---"
  kubectl top pod cpu-intensive 2>/dev/null || true

  echo
  echo "--- Multi-Container Pod ---"
  kubectl top pod multi-container-app \
    --containers \
    2>/dev/null || true

  echo
  echo "--- Warning Events ---"
  kubectl get events \
    -A \
    --field-selector type=Warning \
    --sort-by=.metadata.creationTimestamp \
    2>/dev/null \
    | tail -10 || true

  if [ "$i" -lt "$SAMPLES" ]; then
    sleep "$INTERVAL"
  fi

done

echo
echo "Monitor completed: $(date)"
