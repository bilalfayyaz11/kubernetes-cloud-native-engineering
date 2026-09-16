#!/usr/bin/env bash

set -u

echo "=============================================="
echo " Kubernetes Security Compliance Check"
echo "=============================================="
echo

PASS=0
FAIL=0
WARN=0

pass() {
    echo "✅ $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "❌ $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo "⚠️  $1"
    WARN=$((WARN + 1))
}

echo "1. RBAC / Anonymous Privilege Check"
echo "-----------------------------------"

if kubectl auth can-i '*' '*' \
    --as=system:anonymous \
    2>/dev/null | grep -qx "yes"; then

    fail "Anonymous identity has excessive Kubernetes permissions"
else
    pass "Anonymous identity does not have unrestricted access"
fi

echo
echo "2. Root / Non-Root Workload Check"
echo "---------------------------------"

root_like_containers="$(
kubectl get pods --all-namespaces -o json \
| jq -r '
  .items[] as $pod
  | $pod.spec.containers[]
  | select(
      (.securityContext.runAsNonRoot // false) != true
      and
      (.securityContext.runAsUser // $pod.spec.securityContext.runAsUser // -1) != 1000
      and
      (.securityContext.runAsUser // $pod.spec.securityContext.runAsUser // -1) != 101
    )
  | "\($pod.metadata.namespace)/\($pod.metadata.name) container=\(.name)"
'
)"

if [ -n "$root_like_containers" ]; then
    warn "Some containers do not explicitly enforce the expected non-root configuration:"
    echo "$root_like_containers"
else
    pass "Checked containers explicitly enforce non-root execution"
fi

echo
echo "3. NetworkPolicy Check"
echo "----------------------"

network_policy_count="$(
kubectl get networkpolicies \
  --all-namespaces \
  --no-headers \
  2>/dev/null | wc -l
)"

if [ "$network_policy_count" -eq 0 ]; then
    fail "No NetworkPolicies are configured"
else
    pass "Found $network_policy_count NetworkPolicy resource(s)"
fi

echo
echo "4. Default Service Account Usage"
echo "--------------------------------"

default_sa_pods="$(
kubectl get pods --all-namespaces -o json \
| jq -r '
  .items[]
  | select(
      (.spec.serviceAccountName // "default") == "default"
    )
  | "\(.metadata.namespace)/\(.metadata.name)"
'
)"

if [ -n "$default_sa_pods" ]; then
    warn "Pods using the default service account were found:"
    echo "$default_sa_pods"
else
    pass "No workloads use the default service account"
fi

echo
echo "5. Resource Limit Check"
echo "-----------------------"

containers_without_limits="$(
kubectl get pods --all-namespaces -o json \
| jq -r '
  .items[] as $pod
  | $pod.spec.containers[]
  | select(
      (.resources.limits.cpu // null) == null
      or
      (.resources.limits.memory // null) == null
    )
  | "\($pod.metadata.namespace)/\($pod.metadata.name) container=\(.name)"
'
)"

if [ -n "$containers_without_limits" ]; then
    warn "Containers without complete CPU/memory limits were found:"
    echo "$containers_without_limits"
else
    pass "All checked containers have CPU and memory limits"
fi

echo
echo "6. Privilege Escalation Check"
echo "-----------------------------"

privilege_escalation="$(
kubectl get pods --all-namespaces -o json \
| jq -r '
  .items[] as $pod
  | $pod.spec.containers[]
  | select(
      (.securityContext.allowPrivilegeEscalation // true) != false
    )
  | "\($pod.metadata.namespace)/\($pod.metadata.name) container=\(.name)"
'
)"

if [ -n "$privilege_escalation" ]; then
    warn "Containers without allowPrivilegeEscalation=false:"
    echo "$privilege_escalation"
else
    pass "All checked containers disable privilege escalation"
fi

echo
echo "7. Validating Admission Policy Check"
echo "------------------------------------"

if kubectl get validatingadmissionpolicy \
    workload-security.cloud-native \
    >/dev/null 2>&1; then

    pass "Workload ValidatingAdmissionPolicy is installed"
else
    fail "Workload ValidatingAdmissionPolicy is missing"
fi

echo
echo "8. Admission Policy Binding Check"
echo "---------------------------------"

if kubectl get validatingadmissionpolicybinding \
    workload-security-binding \
    >/dev/null 2>&1; then

    pass "Admission policy binding is active"
else
    fail "Admission policy binding is missing"
fi

echo
echo "=============================================="
echo " Compliance Summary"
echo "=============================================="
echo "PASS : $PASS"
echo "WARN : $WARN"
echo "FAIL : $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo
    echo "Overall status: NON-COMPLIANT"
    exit 1
fi

echo
echo "Overall status: NO CRITICAL FAILURES"
exit 0
