#!/bin/bash
set +e

echo "=================================================="
echo " KUBERNETES SECRET ACCESS MONITOR"
echo "=================================================="

echo
echo "===== SECRET INVENTORY ====="

kubectl get secrets -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,TYPE:.type,CREATED:.metadata.creationTimestamp'

echo
echo "===== PODS USING SECRET ENV REFERENCES ====="

kubectl get pods -A -o json \
  | jq -r '
      .items[]
      | . as $pod
      | .spec.containers[]?
      | . as $container
      | .env[]?
      | select(.valueFrom.secretKeyRef != null)
      | "\($pod.metadata.namespace)/\($pod.metadata.name) container=\($container.name) -> secret/\(.valueFrom.secretKeyRef.name)"
    ' \
  | sort -u

echo
echo "===== PODS USING SECRET VOLUMES ====="

kubectl get pods -A -o json \
  | jq -r '
      .items[]
      | . as $pod
      | .spec.volumes[]?
      | select(.secret != null)
      | "\($pod.metadata.namespace)/\($pod.metadata.name) -> secret/\(.secret.secretName)"
    ' \
  | sort -u

echo
echo "===== SERVICE ACCOUNTS WITH SECRET RBAC ====="

kubectl get roles,clusterroles,rolebindings,clusterrolebindings -A -o json \
  | jq -r '
      .items[]
      | select(
          (.rules // [])
          | any(
              (.resources // [])
              | index("secrets")
            )
        )
      | "\(.kind) \(.metadata.namespace // "-")/\(.metadata.name)"
    ' 2>/dev/null \
  || true

echo
echo "===== SECRET-READER AUTHORIZATION ====="

for action in \
  "get secret/user-credentials" \
  "get secret/database-secret" \
  "get secret/tls-secret" \
  "list secrets" \
  "create secrets" \
  "delete secret/user-credentials"; do

  echo -n "$action -> "

  kubectl auth can-i \
    $action \
    --as=system:serviceaccount:default:secret-reader \
    -n default
done

echo
echo "===== K3S ENCRYPTION STATUS ====="

sudo k3s secrets-encrypt status 2>&1

echo
echo "=================================================="
echo " SECRET ACCESS MONITOR COMPLETE"
echo "=================================================="
