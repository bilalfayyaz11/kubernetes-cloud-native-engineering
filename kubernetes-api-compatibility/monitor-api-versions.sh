#!/bin/bash
set -euo pipefail

echo "=================================================="
echo " KUBERNETES API VERSION MONITOR"
echo "=================================================="

echo
echo "===== CLIENT VERSION ====="
kubectl version --client

echo
echo "===== SERVER VERSION ====="
kubectl version -o json | jq -r '
  .serverVersion.gitVersion // "server-version-unavailable"
'

echo
echo "===== RELEVANT AVAILABLE API VERSIONS ====="
kubectl api-versions | \
  grep -E '^(apps/|networking.k8s.io/|policy/|extensions/)' \
  | sort || true

echo
echo "===== REMOVED API CAPABILITY CHECK ====="

for api in \
  extensions/v1beta1 \
  policy/v1beta1
do
    if kubectl api-versions | grep -qx "$api"; then
        echo "WARNING: $api is still served"
    else
        echo "PASS: $api is not served"
    fi
done

echo
echo "===== LIVE DEPLOYMENT APIS ====="

kubectl get deployments \
  -A \
  -o json | jq -r '
    .items[] |
    "\(.metadata.namespace)/\(.metadata.name) -> \(.apiVersion)"
  '

echo
echo "===== LIVE INGRESS APIS ====="

kubectl get ingresses \
  -A \
  -o json | jq -r '
    .items[] |
    "\(.metadata.namespace)/\(.metadata.name) -> \(.apiVersion)"
  ' 2>/dev/null || true

echo
echo "===== POD SECURITY NAMESPACE LABELS ====="

kubectl get namespaces \
  -o json | jq -r '
    .items[] |
    select(
      .metadata.labels["pod-security.kubernetes.io/enforce"] != null
    ) |
    "\(.metadata.name) -> enforce=\(.metadata.labels["pod-security.kubernetes.io/enforce"])"
  '

echo
echo "=================================================="
echo " MONITOR COMPLETE"
echo "=================================================="
