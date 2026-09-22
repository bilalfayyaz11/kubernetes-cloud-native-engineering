#!/usr/bin/env bash
set +e

echo "=================================================="
echo " KUBERNETES SCHEDULING MONITOR"
echo "=================================================="

echo
echo "=== Nodes and Scheduling Labels ==="

kubectl get nodes \
  -L tier,disk,scheduling.demo/node,scheduling.demo/role \
  -o wide

echo
echo "=== Node Taints ==="

for NODE in $(kubectl get nodes -o name | cut -d/ -f2); do

  echo
  echo "Node: $NODE"

  TAINTS="$(
    kubectl get node "$NODE" \
      -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{"\n"}{end}'
  )"

  if [ -n "$TAINTS" ]; then
    echo "$TAINTS"
  else
    echo "No taints"
  fi

done

echo
echo "=== Workload Distribution ==="

kubectl get pods \
  -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,NODE:.spec.nodeName' \
  --sort-by=.spec.nodeName

echo
echo "=== Pending Pods ==="

kubectl get pods \
  -A \
  --field-selector=status.phase=Pending \
  -o wide

echo
echo "=== Deployment State ==="

kubectl get deployments -A

echo
echo "=== Recent Events ==="

kubectl get events \
  -A \
  --sort-by=.metadata.creationTimestamp \
  | tail -30

echo
echo "=================================================="
