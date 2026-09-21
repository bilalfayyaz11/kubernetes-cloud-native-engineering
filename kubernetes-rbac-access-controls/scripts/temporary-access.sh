#!/usr/bin/env bash
set +e

NS="development"
SA="temp-admin"
BINDING="temp-admin-binding"

grant_access() {
  kubectl create serviceaccount "$SA" \
    -n "$NS" \
    --dry-run=client \
    -o yaml \
    | kubectl apply -f -

  cat <<YAML | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $BINDING
  namespace: $NS
subjects:
  - kind: ServiceAccount
    name: $SA
    namespace: $NS
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: dev-full-access
YAML

  echo "Temporary access granted."
}

revoke_access() {
  kubectl delete rolebinding "$BINDING" \
    -n "$NS" \
    --ignore-not-found=true

  kubectl delete serviceaccount "$SA" \
    -n "$NS" \
    --ignore-not-found=true

  echo "Temporary access revoked."
}

case "${1:-}" in
  grant)
    grant_access
    ;;
  revoke)
    revoke_access
    ;;
  *)
    echo "Usage: $0 grant|revoke"
    exit 1
    ;;
esac
