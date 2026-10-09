#!/bin/bash

set +e

NAMESPACE="kernel-hardening"
APP="hardened-web"
PROFILE="k8s-restricted-app"

PASS=0
FAIL=0

pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
}

echo "=================================================="
echo " KUBERNETES KERNEL SECURITY VERIFICATION"
echo "=================================================="

POD="$(
  kubectl get pods \
    -n "$NAMESPACE" \
    -l app="$APP" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' \
    2>/dev/null
)"

echo
echo "===== Kubernetes API ====="

if kubectl get --raw='/readyz' >/dev/null 2>&1; then
  pass "Kubernetes API healthy"
else
  fail "Kubernetes API unavailable"
fi

echo
echo "===== Hardened Workload ====="

READY="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.status.readyReplicas}' \
    2>/dev/null
)"

DESIRED="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.replicas}' \
    2>/dev/null
)"

if [ -n "$READY" ] && \
   [ "$READY" = "$DESIRED" ]; then
  pass "all hardened workload replicas ready"
else
  fail "hardened workload replicas not fully ready"
fi

if [ -z "$POD" ]; then
  fail "no running hardened workload pod found"

  echo
  echo "Passed: $PASS"
  echo "Failed: $FAIL"

  exit 1
fi

echo "Selected pod: $POD"

echo
echo "===== Seccomp ====="

SECCOMP_MODE="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- sh -c \
    "awk '/^Seccomp:/{print \$2}' /proc/self/status" \
    2>/dev/null
)"

SECCOMP_FILTERS="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- sh -c \
    "awk '/^Seccomp_filters:/{print \$2}' /proc/self/status" \
    2>/dev/null
)"

DECLARED_SECCOMP="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}' \
    2>/dev/null
)"

DECLARED_PROFILE="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.localhostProfile}' \
    2>/dev/null
)"

if [ "$DECLARED_SECCOMP" = "Localhost" ] && \
   [ "$DECLARED_PROFILE" = "profiles/restricted-profile.json" ]; then
  pass "custom Localhost Seccomp profile declared"
else
  fail "expected custom Seccomp declaration missing"
fi

if [ "$SECCOMP_MODE" = "2" ]; then
  pass "Seccomp filter mode active"
else
  fail "Seccomp filter mode inactive"
fi

if [ -n "$SECCOMP_FILTERS" ] && \
   [ "$SECCOMP_FILTERS" -ge 1 ] 2>/dev/null; then
  pass "Seccomp filter installed"
else
  fail "Seccomp filter count unavailable"
fi

echo
echo "===== AppArmor ====="

APPARMOR_RUNTIME="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- cat /proc/self/attr/current \
    2>/dev/null
)"

if printf '%s\n' "$APPARMOR_RUNTIME" \
  | grep -q "$PROFILE"; then
  pass "custom AppArmor profile active"
else
  fail "custom AppArmor profile inactive"
fi

echo
echo "===== User Identity ====="

UID_VALUE="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- id -u \
    2>/dev/null
)"

if [ "$UID_VALUE" = "10001" ]; then
  pass "workload running as non-root UID 10001"
else
  fail "unexpected workload UID"
fi

echo
echo "===== Privilege Escalation ====="

APE="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' \
    2>/dev/null
)"

if [ "$APE" = "false" ]; then
  pass "privilege escalation disabled"
else
  fail "privilege escalation control missing"
fi

echo
echo "===== Capability Restrictions ====="

CAP_DROP="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.drop[*]}' \
    2>/dev/null
)"

if printf '%s\n' "$CAP_DROP" | grep -qw ALL; then
  pass "all Linux capabilities dropped"
else
  fail "capability drop policy missing"
fi

echo
echo "===== Read-Only Root Filesystem ====="

READ_ONLY="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' \
    2>/dev/null
)"

if [ "$READ_ONLY" = "true" ]; then
  pass "read-only root filesystem configured"
else
  fail "read-only root filesystem not configured"
fi

ROOT_WRITE="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- sh -c \
    'touch /security-root-write-test >/dev/null 2>&1; echo $?' \
    2>/dev/null
)"

if [ "$ROOT_WRITE" != "0" ]; then
  pass "root filesystem write blocked at runtime"
else
  fail "root filesystem unexpectedly writable"

  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- rm -f /security-root-write-test \
    >/dev/null 2>&1 || true
fi

echo
echo "===== Writable Temporary Storage ====="

if kubectl exec \
  -n "$NAMESPACE" \
  "$POD" \
  -- sh -c \
  'echo test > /tmp/security-validation && test -s /tmp/security-validation' \
  >/dev/null 2>&1; then
  pass "controlled writable /tmp available"
else
  fail "controlled /tmp write failed"
fi

echo
echo "===== Sensitive File Restriction ====="

SHADOW_RC="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- sh -c \
    'head -c 1 /etc/shadow >/dev/null 2>&1; echo $?' \
    2>/dev/null
)"

if [ "$SHADOW_RC" != "0" ]; then
  pass "sensitive /etc/shadow access blocked"
else
  fail "/etc/shadow unexpectedly readable"
fi

echo
echo "===== Dangerous Operation ====="

MOUNT_RC="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- sh -c \
    'mkdir -p /tmp/security-mount; mount -t tmpfs tmpfs /tmp/security-mount >/dev/null 2>&1; echo $?' \
    2>/dev/null
)"

if [ "$MOUNT_RC" != "0" ]; then
  pass "mount operation blocked"
else
  fail "mount operation unexpectedly succeeded"
fi

echo
echo "===== ServiceAccount Token ====="

TOKEN="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- sh -c \
    '[ -e /var/run/secrets/kubernetes.io/serviceaccount/token ] && echo PRESENT || echo ABSENT' \
    2>/dev/null
)"

if [ "$TOKEN" = "ABSENT" ]; then
  pass "ServiceAccount token automount disabled"
else
  fail "ServiceAccount token present"
fi

echo
echo "===== Service Functionality ====="

if kubectl exec \
  -n "$NAMESPACE" \
  hardened-client \
  -- wget \
  -qO- \
  --timeout=5 \
  http://hardened-web \
  2>/dev/null \
  | grep -q "Kernel Hardened Workload"; then
  pass "hardened application remains functional"
else
  fail "hardened application functionality test failed"
fi

echo
echo "=================================================="
echo " SECURITY VALIDATION SUMMARY"
echo "=================================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"

if [ "$FAIL" -eq 0 ]; then
  echo "OVERALL RESULT: PASS"
  exit 0
else
  echo "OVERALL RESULT: FAIL"
  exit 1
fi
