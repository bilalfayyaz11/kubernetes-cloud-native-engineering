#!/usr/bin/env bash

set -u

NS="threat-modeling"

echo "===== MITIGATION VALIDATION ====="

echo
echo "NetworkPolicies:"
kubectl get networkpolicy \
  -n "$NS"

echo
echo "Dedicated ServiceAccounts:"
kubectl get serviceaccounts \
  -n "$NS"

echo
echo "Restricted ServiceAccount permissions:"

kubectl auth can-i \
  get pods \
  --as=system:serviceaccount:${NS}:restricted-sa \
  -n "$NS"

kubectl auth can-i \
  get secrets \
  --as=system:serviceaccount:${NS}:restricted-sa \
  -n "$NS"

echo
echo "Pod security controls:"

kubectl get pod secure-pod \
  -n "$NS" \
  -o json \
  | jq '{
      serviceAccount: .spec.serviceAccountName,
      seccomp: .spec.securityContext.seccompProfile,
      containerSecurityContext:
        .spec.containers[0].securityContext
    }'
