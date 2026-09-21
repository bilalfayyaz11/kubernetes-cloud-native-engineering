#!/usr/bin/env bash
set +e

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "PASS: $1"
  PASS_COUNT=$((PASS_COUNT+1))
}

fail() {
  echo "FAIL: $1"
  FAIL_COUNT=$((FAIL_COUNT+1))
}

run_expect_success() {
  DESC="$1"
  shift

  echo
  echo "TEST: $DESC"

  "$@"
  RC=$?

  if [ "$RC" -eq 0 ]; then
    pass "$DESC"
  else
    fail "$DESC"
  fi
}

run_expect_failure() {
  DESC="$1"
  shift

  echo
  echo "TEST: $DESC"

  "$@"
  RC=$?

  if [ "$RC" -ne 0 ]; then
    pass "$DESC"
  else
    fail "$DESC"
  fi
}

echo "=============================================="
echo " Kubernetes RBAC Permission Validation"
echo "=============================================="

echo
echo "=== DEVELOPMENT TEAM ==="

run_expect_success \
  "dev-team can list Pods in development" \
  kubectl exec -n development dev-pod -- \
  kubectl get pods -n development

run_expect_success \
  "dev-team can create ConfigMaps in development" \
  kubectl exec -n development dev-pod -- \
  kubectl create configmap rbac-dev-test \
  --from-literal=test=value \
  -n development

kubectl delete configmap rbac-dev-test \
  -n development \
  --ignore-not-found=true >/dev/null 2>&1 || true

run_expect_success \
  "dev-team can create Deployments in development" \
  kubectl exec -n development dev-pod -- \
  kubectl create deployment rbac-dev-deploy \
  --image=nginx:1.27 \
  -n development

kubectl delete deployment rbac-dev-deploy \
  -n development \
  --ignore-not-found=true >/dev/null 2>&1 || true

run_expect_failure \
  "dev-team cannot list Pods in production" \
  kubectl exec -n development dev-pod -- \
  kubectl get pods -n production

echo
echo "=== PRODUCTION TEAM ==="

run_expect_success \
  "prod-team can list Pods in production" \
  kubectl exec -n production prod-pod -- \
  kubectl get pods -n production

run_expect_success \
  "prod-team can view Deployments in production" \
  kubectl exec -n production prod-pod -- \
  kubectl get deployments -n production

run_expect_success \
  "prod-team can patch Deployments in production" \
  kubectl exec -n production prod-pod -- \
  kubectl patch deployment prod-app \
  -n production \
  --type merge \
  -p '{"metadata":{"annotations":{"rbac-test":"validated"}}}'

run_expect_failure \
  "prod-team cannot create Secrets in production" \
  kubectl exec -n production prod-pod -- \
  kubectl create secret generic unauthorized-secret \
  --from-literal=value=test \
  -n production

kubectl delete secret unauthorized-secret \
  -n production \
  --ignore-not-found=true >/dev/null 2>&1 || true

run_expect_failure \
  "prod-team cannot delete Deployments in production" \
  kubectl exec -n production prod-pod -- \
  kubectl delete deployment prod-app \
  -n production

run_expect_failure \
  "prod-team cannot list Pods in development" \
  kubectl exec -n production prod-pod -- \
  kubectl get pods -n development

echo
echo "=== READ-ONLY IDENTITY ==="

run_expect_success \
  "readonly-user can list Pods in testing" \
  kubectl exec -n testing readonly-pod -- \
  kubectl get pods -n testing

run_expect_success \
  "readonly-user can list namespaces" \
  kubectl exec -n testing readonly-pod -- \
  kubectl get namespaces

run_expect_success \
  "readonly-user can list nodes" \
  kubectl exec -n testing readonly-pod -- \
  kubectl get nodes

run_expect_success \
  "readonly-user can view Pods in development through ClusterRole" \
  kubectl exec -n testing readonly-pod -- \
  kubectl get pods -n development

run_expect_failure \
  "readonly-user cannot create Pods in testing" \
  kubectl exec -n testing readonly-pod -- \
  kubectl run unauthorized-pod \
  --image=nginx:1.27 \
  -n testing

kubectl delete pod unauthorized-pod \
  -n testing \
  --ignore-not-found=true >/dev/null 2>&1 || true

run_expect_failure \
  "readonly-user cannot create Secrets in testing" \
  kubectl exec -n testing readonly-pod -- \
  kubectl create secret generic unauthorized-secret \
  --from-literal=value=test \
  -n testing

kubectl delete secret unauthorized-secret \
  -n testing \
  --ignore-not-found=true >/dev/null 2>&1 || true

echo
echo "=============================================="
echo " RESULT SUMMARY"
echo "=============================================="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "OVERALL RESULT: PASS"
  exit 0
else
  echo "OVERALL RESULT: FAIL"
  exit 1
fi
