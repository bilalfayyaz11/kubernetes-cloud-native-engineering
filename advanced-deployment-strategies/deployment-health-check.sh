#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="deployment-strategies"

echo "======================================"
echo " Deployment Health Check"
echo "======================================"

echo
echo "===== DEPLOYMENTS ====="

kubectl get deployments \
  -n "$NAMESPACE" \
  -l app=sample-app \
  -o wide


echo
echo "===== PODS ====="

kubectl get pods \
  -n "$NAMESPACE" \
  -l app=sample-app \
  -o wide


echo
echo "===== SERVICES ====="

kubectl get services \
  -n "$NAMESPACE" \
  -l app=sample-app


echo
echo "===== PRODUCTION SERVICE SELECTOR ====="

kubectl get service sample-app-service \
  -n "$NAMESPACE" \
  -o jsonpath='{.spec.selector}{"\n"}'


echo
echo "===== ENDPOINTSLICE ====="

kubectl get endpointslice \
  -n "$NAMESPACE" \
  -l kubernetes.io/service-name=sample-app-service \
  -o wide


echo
echo "===== RECENT EVENTS ====="

kubectl get events \
  -n "$NAMESPACE" \
  --sort-by='.metadata.creationTimestamp' \
  | tail -n 20


echo
echo "===== RESOURCE USAGE ====="

kubectl top pods \
  -n "$NAMESPACE" \
  -l app=sample-app \
  --containers


echo
echo "===== ROLLOUT HISTORY — V1 ====="

kubectl rollout history \
  deployment/sample-app-v1 \
  -n "$NAMESPACE"


echo
echo "===== ROLLOUT HISTORY — V2 ====="

kubectl rollout history \
  deployment/sample-app-v2 \
  -n "$NAMESPACE"


echo
echo "===== ROLLOUT HISTORY — V3 ====="

kubectl rollout history \
  deployment/sample-app-v3 \
  -n "$NAMESPACE"


echo
echo "===== CURRENT DEPLOYMENT CONDITIONS ====="

for DEPLOYMENT in sample-app-v1 sample-app-v2 sample-app-v3; do

    echo
    echo "--- ${DEPLOYMENT} ---"

    kubectl get deployment "$DEPLOYMENT" \
      -n "$NAMESPACE" \
      -o jsonpath='{range .status.conditions[*]}{.type}{"="}{.status}{" reason="}{.reason}{"\n"}{end}'
done
