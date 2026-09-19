#!/bin/bash
set -e

NAMESPACE="rollout-demo"
DEPLOYMENT="nginx-deployment"

echo "=================================================="
echo " DEPLOYMENT REVISION ANALYSIS"
echo "=================================================="

echo
echo "===== DEPLOYMENT STATUS ====="
kubectl get deployment "$DEPLOYMENT" \
  -n "$NAMESPACE" \
  -o wide

echo
echo "===== ROLLOUT HISTORY ====="
kubectl rollout history deployment/"$DEPLOYMENT" \
  -n "$NAMESPACE"

echo
echo "===== REPLICASETS ====="
kubectl get replicasets \
  -n "$NAMESPACE" \
  -l app=nginx \
  -o custom-columns='NAME:.metadata.name,REVISION:.metadata.annotations.deployment\.kubernetes\.io/revision,DESIRED:.spec.replicas,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image'

echo
echo "===== PODS ====="
kubectl get pods \
  -n "$NAMESPACE" \
  -l app=nginx \
  -o wide

echo
echo "===== UPDATE STRATEGY ====="
kubectl get deployment "$DEPLOYMENT" \
  -n "$NAMESPACE" \
  -o json | jq '.spec.strategy'

echo
echo "===== REVISION HISTORY LIMIT ====="
kubectl get deployment "$DEPLOYMENT" \
  -n "$NAMESPACE" \
  -o jsonpath='revisionHistoryLimit={.spec.revisionHistoryLimit}{"\n"}'

echo
echo "=================================================="
echo " ANALYSIS COMPLETE"
echo "=================================================="
