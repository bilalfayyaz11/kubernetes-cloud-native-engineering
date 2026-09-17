#!/usr/bin/env bash

set -u

NS="threat-modeling"

echo "===== KUBERNETES THREAT MODEL BASELINE ====="

echo
echo "=== Workloads ==="
kubectl get deployments \
  -n "$NS"

echo
echo "=== Services ==="
kubectl get services \
  -n "$NS"

echo
echo "=== ServiceAccounts ==="
kubectl get serviceaccounts \
  -n "$NS"

echo
echo "=== NetworkPolicies ==="
NETWORK_POLICY_COUNT=$(
  kubectl get networkpolicy \
    -n "$NS" \
    --no-headers \
    2>/dev/null \
  | wc -l
)

echo "Count: $NETWORK_POLICY_COUNT"

if [ "$NETWORK_POLICY_COUNT" -eq 0 ]; then
  echo "RISK: unrestricted workload east-west networking"
fi

echo
echo "=== RBAC Bindings ==="
kubectl get rolebindings \
  -n "$NS" \
  2>/dev/null || true

echo
echo "=== Pod Security Admission ==="
kubectl get namespace "$NS" \
  --show-labels

echo
echo "=== HostPath Usage ==="
kubectl get pods \
  -n "$NS" \
  -o json \
  | jq -r '
      .items[]
      |
      select(
        any(.spec.volumes[]?; has("hostPath"))
      )
      |
      .metadata.name
    '

echo
echo "=== Privileged Containers ==="
kubectl get pods \
  -n "$NS" \
  -o json \
  | jq -r '
      .items[]
      |
      .metadata.name as $pod
      |
      .spec.containers[]
      |
      select(.securityContext.privileged == true)
      |
      "\($pod)/\(.name)"
    '

echo
echo "=== ServiceAccount Assignment ==="
kubectl get pods \
  -n "$NS" \
  -o json \
  | jq -r '
      .items[]
      |
      [
        .metadata.name,
        (.spec.serviceAccountName // "default")
      ]
      | @tsv
    '
