#!/bin/bash

set +e

echo "=== Kubernetes Troubleshooting Log Collection ==="
echo "Timestamp: $(date)"
echo

echo "=== Cluster Info ==="
kubectl cluster-info 2>/dev/null || echo "Cluster info unavailable"
echo

echo "=== Node Status ==="
kubectl get nodes -o wide 2>/dev/null || echo "Node information unavailable"
echo

echo "=== System Pods Status ==="
kubectl get pods -n kube-system -o wide 2>/dev/null || echo "kube-system unavailable"
echo

echo "=== Recent Events ==="
kubectl get events -A \
  --sort-by=.metadata.creationTimestamp \
  2>/dev/null | tail -50
echo

echo "=== Recent kubelet Logs ==="
sudo journalctl \
  -u kubelet \
  --no-pager \
  --lines=40 2>/dev/null || echo "kubelet logs unavailable"
echo

APISERVER_POD="$(kubectl get pods \
  -n kube-system \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  2>/dev/null | grep '^kube-apiserver-' | head -1)"

echo "=== API Server Logs ==="
if [ -n "$APISERVER_POD" ]; then
  kubectl logs \
    -n kube-system \
    "$APISERVER_POD" \
    --tail=40 2>/dev/null || echo "API server logs unavailable"
else
  echo "API server pod not found"
fi
echo

CONTROLLER_POD="$(kubectl get pods \
  -n kube-system \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  2>/dev/null | grep '^kube-controller-manager-' | head -1)"

echo "=== Controller Manager Logs ==="
if [ -n "$CONTROLLER_POD" ]; then
  kubectl logs \
    -n kube-system \
    "$CONTROLLER_POD" \
    --tail=40 2>/dev/null || echo "Controller manager logs unavailable"
else
  echo "Controller manager pod not found"
fi
echo

SCHEDULER_POD="$(kubectl get pods \
  -n kube-system \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  2>/dev/null | grep '^kube-scheduler-' | head -1)"

echo "=== Scheduler Logs ==="
if [ -n "$SCHEDULER_POD" ]; then
  kubectl logs \
    -n kube-system \
    "$SCHEDULER_POD" \
    --tail=40 2>/dev/null || echo "Scheduler logs unavailable"
else
  echo "Scheduler pod not found"
fi
echo

echo "=== Error Pattern Summary ==="

if [ -n "$APISERVER_POD" ]; then
  echo "--- API Server Errors ---"
  kubectl logs \
    -n kube-system \
    "$APISERVER_POD" \
    --tail=500 2>/dev/null \
    | grep -Ei 'error|failed|fatal|panic|timeout' \
    | tail -20 \
    || echo "No API server errors detected"
fi

echo
echo "--- Kubelet Errors ---"

sudo journalctl \
  -u kubelet \
  --since "30 minutes ago" \
  --no-pager 2>/dev/null \
  | grep -Ei 'error|failed|fatal|panic|timeout' \
  | tail -20 \
  || echo "No kubelet errors detected"

echo
echo "=== Collection Complete ==="
