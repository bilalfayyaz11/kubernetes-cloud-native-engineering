#!/bin/bash
set -e

NAMESPACE="access-control"

echo "=================================================="
echo " RBAC AUDIT REPORT"
echo "=================================================="
echo "Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "Namespace: $NAMESPACE"

echo
echo "===== SERVICEACCOUNTS ====="

kubectl get serviceaccounts \
  -n "$NAMESPACE" \
  -o custom-columns='NAME:.metadata.name,AUTOMOUNT:.automountServiceAccountToken'

echo
echo "===== ROLES ====="

kubectl get roles \
  -n "$NAMESPACE"

echo
for role in $(kubectl get roles \
  -n "$NAMESPACE" \
  -o jsonpath='{.items[*].metadata.name}')
do
    echo "----- ROLE: $role -----"
    kubectl describe role \
      "$role" \
      -n "$NAMESPACE"
    echo
done

echo
echo "===== ROLEBINDINGS ====="

kubectl get rolebindings \
  -n "$NAMESPACE" \
  -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name'

echo
echo "===== CUSTOM CLUSTERROLE ====="

kubectl get clusterrole monitoring-readonly \
  -o yaml

echo
echo "===== CUSTOM CLUSTERROLEBINDING ====="

kubectl get clusterrolebinding monitoring-readonly-binding \
  -o yaml

echo
echo "===== AUTHORIZATION MATRIX ====="

identities=(
  "webapp-service-account"
  "database-service-account"
  "monitoring-service-account"
  "minimal-service-account"
)

for sa in "${identities[@]}"
do
    identity="system:serviceaccount:${NAMESPACE}:${sa}"

    echo
    echo "--- $sa ---"

    for test in \
      "get pods" \
      "list pods" \
      "create pods" \
      "get services" \
      "get configmaps" \
      "get secrets"
    do
        verb="$(echo "$test" | awk '{print $1}')"
        resource="$(echo "$test" | awk '{print $2}')"

        result="$(
          kubectl auth can-i \
            "$verb" "$resource" \
            -n "$NAMESPACE" \
            --as="$identity" \
            2>/dev/null || true
        )"

        printf "%-25s %s\n" "$test" "$result"
    done
done

echo
echo "=================================================="
echo " RBAC AUDIT COMPLETE"
echo "=================================================="
