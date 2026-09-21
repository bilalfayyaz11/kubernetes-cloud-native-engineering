#!/usr/bin/env bash
set +e

DEV_ID="system:serviceaccount:development:dev-team"
PROD_ID="system:serviceaccount:production:prod-team"
READONLY_ID="system:serviceaccount:testing:readonly-user"
CONFIG_ID="system:serviceaccount:development:config-operator"

echo "=================================================="
echo " Kubernetes RBAC Audit Report"
echo "=================================================="

echo
echo "=== SERVICE ACCOUNTS ==="
kubectl get serviceaccounts -A

echo
echo "=== NAMESPACE ROLES ==="
kubectl get roles -A

echo
echo "=== ROLEBINDINGS ==="
kubectl get rolebindings -A

echo
echo "=== CUSTOM CLUSTERROLE ==="
kubectl get clusterrole cluster-viewer 2>/dev/null || true

echo
echo "=== CUSTOM CLUSTERROLEBINDING ==="
kubectl get clusterrolebinding cluster-viewer-binding 2>/dev/null || true

echo
echo "=== DEVELOPMENT TEAM - EFFECTIVE PERMISSIONS ==="
kubectl auth can-i --list \
  --as="$DEV_ID" \
  -n development

echo
echo "=== PRODUCTION TEAM - EFFECTIVE PERMISSIONS ==="
kubectl auth can-i --list \
  --as="$PROD_ID" \
  -n production

echo
echo "=== READONLY USER - EFFECTIVE PERMISSIONS ==="
kubectl auth can-i --list \
  --as="$READONLY_ID" \
  -n testing

echo
echo "=== CONFIG OPERATOR - EFFECTIVE PERMISSIONS ==="
kubectl auth can-i --list \
  --as="$CONFIG_ID" \
  -n development

echo
echo "=== TARGETED AUTHORIZATION CHECKS ==="

echo
echo "--- Development identity ---"
echo -n "create pods in development: "
kubectl auth can-i create pods \
  --as="$DEV_ID" \
  -n development

echo -n "delete deployments in development: "
kubectl auth can-i delete deployments \
  --as="$DEV_ID" \
  -n development

echo -n "get pods in production: "
kubectl auth can-i get pods \
  --as="$DEV_ID" \
  -n production

echo
echo "--- Production identity ---"
echo -n "list pods in production: "
kubectl auth can-i list pods \
  --as="$PROD_ID" \
  -n production

echo -n "patch deployments in production: "
kubectl auth can-i patch deployments \
  --as="$PROD_ID" \
  -n production

echo -n "delete deployments in production: "
kubectl auth can-i delete deployments \
  --as="$PROD_ID" \
  -n production

echo -n "create secrets in production: "
kubectl auth can-i create secrets \
  --as="$PROD_ID" \
  -n production

echo
echo "--- Readonly identity ---"
echo -n "list namespaces: "
kubectl auth can-i list namespaces \
  --as="$READONLY_ID"

echo -n "list nodes: "
kubectl auth can-i list nodes \
  --as="$READONLY_ID"

echo -n "list pods in development: "
kubectl auth can-i list pods \
  --as="$READONLY_ID" \
  -n development

echo -n "create pods in testing: "
kubectl auth can-i create pods \
  --as="$READONLY_ID" \
  -n testing

echo -n "create secrets in testing: "
kubectl auth can-i create secrets \
  --as="$READONLY_ID" \
  -n testing

echo
echo "--- Exact resource identity ---"
echo -n "get app-config: "
kubectl auth can-i get configmap/app-config \
  --as="$CONFIG_ID" \
  -n development

echo -n "get database-config: "
kubectl auth can-i get configmap/database-config \
  --as="$CONFIG_ID" \
  -n development

echo -n "get unrelated-config: "
kubectl auth can-i get configmap/unrelated-config \
  --as="$CONFIG_ID" \
  -n development

echo
echo "=================================================="
echo " RBAC Audit Complete"
echo "=================================================="
