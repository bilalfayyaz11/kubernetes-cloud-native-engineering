#!/bin/bash

set +e

NAMESPACE="kernel-hardening"
APP="hardened-web"
PASS=0
FAIL=0

check() {
  if [ "$1" -eq 0 ]; then
    echo "PASS: $2"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $2"
    FAIL=$((FAIL + 1))
  fi
}

POD="$(
  kubectl get pods \
    -n "$NAMESPACE" \
    -l app="$APP" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' \
    2>/dev/null
)"

echo "=================================================="
echo " KERNEL HARDENING COMPLIANCE CHECK"
echo "=================================================="

echo
echo "Control 1 — Seccomp"

kubectl exec \
  -n "$NAMESPACE" \
  "$POD" \
  -- sh -c \
  "grep -q '^Seccomp:[[:space:]]*2' /proc/self/status" \
  >/dev/null 2>&1

check $? "Seccomp filtering active"

echo
echo "Control 2 — AppArmor"

kubectl exec \
  -n "$NAMESPACE" \
  "$POD" \
  -- cat /proc/self/attr/current \
  2>/dev/null \
  | grep -q "k8s-restricted-app"

check $? "AppArmor confinement active"

echo
echo "Control 3 — Non-root"

UID="$(
  kubectl exec \
    -n "$NAMESPACE" \
    "$POD" \
    -- id -u \
    2>/dev/null
)"

[ "$UID" = "10001" ]

check $? "non-root UID enforced"

echo
echo "Control 4 — Capabilities"

CAPS="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.drop[*]}' \
    2>/dev/null
)"

printf '%s\n' "$CAPS" | grep -qw ALL

check $? "all capabilities dropped"

echo
echo "Control 5 — Privilege Escalation"

APE="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' \
    2>/dev/null
)"

[ "$APE" = "false" ]

check $? "privilege escalation disabled"

echo
echo "Control 6 — Read-only Root"

RO="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' \
    2>/dev/null
)"

[ "$RO" = "true" ]

check $? "read-only root filesystem configured"

echo
echo "Control 7 — ServiceAccount Token"

TOKEN="$(
  kubectl get deployment "$APP" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.automountServiceAccountToken}' \
    2>/dev/null
)"

[ "$TOKEN" = "false" ]

check $? "ServiceAccount token automount disabled"

echo
echo "=================================================="
echo " COMPLIANCE SUMMARY"
echo "=================================================="

TOTAL=$((PASS + FAIL))

if [ "$TOTAL" -gt 0 ]; then
  SCORE=$((PASS * 100 / TOTAL))
else
  SCORE=0
fi

echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Score:  ${SCORE}%"

if [ "$FAIL" -eq 0 ]; then
  echo "COMPLIANCE RESULT: PASS"
  exit 0
else
  echo "COMPLIANCE RESULT: FAIL"
  exit 1
fi
