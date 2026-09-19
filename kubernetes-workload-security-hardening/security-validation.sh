#!/usr/bin/env bash
set +e

POD_NAME="$1"
NAMESPACE="${2:-default}"

if [ -z "$POD_NAME" ]; then
    echo "Usage: $0 <pod-name> [namespace]"
    exit 1
fi

echo "=================================================="
echo " SECURITY VALIDATION"
echo "=================================================="
echo "Pod       : $POD_NAME"
echo "Namespace : $NAMESPACE"
echo

if ! kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" >/dev/null 2>&1
then
    echo "FAIL: Pod not found."
    exit 1
fi

echo "===== NON-ROOT CHECK ====="

USER_ID="$(kubectl exec \
  -n "$NAMESPACE" \
  "$POD_NAME" -- \
  id -u 2>/dev/null)"

if [ "$USER_ID" = "0" ]; then
    echo "FAIL: Running as root (UID 0)."
else
    echo "PASS: Running as non-root UID $USER_ID."
fi

echo
echo "===== READ-ONLY ROOT FILESYSTEM ====="

if kubectl exec \
  -n "$NAMESPACE" \
  "$POD_NAME" -- \
  touch /security-validation-write \
  >/dev/null 2>&1
then
    kubectl exec \
      -n "$NAMESPACE" \
      "$POD_NAME" -- \
      rm -f /security-validation-write \
      >/dev/null 2>&1 || true

    echo "FAIL: Root filesystem is writable."
else
    echo "PASS: Root filesystem is read-only."
fi

echo
echo "===== EFFECTIVE CAPABILITIES ====="

CAPS="$(kubectl exec \
  -n "$NAMESPACE" \
  "$POD_NAME" -- \
  sh -c "awk '/^CapEff:/ {print \$2}' /proc/1/status" \
  2>/dev/null)"

echo "CapEff: $CAPS"

if [ "$CAPS" = "0000000000000000" ]; then
    echo "PASS: No effective Linux capabilities."
else
    echo "INFO: Effective capabilities present."
fi

echo
echo "===== PRIVILEGE ESCALATION ====="

NO_NEW_PRIVS="$(kubectl exec \
  -n "$NAMESPACE" \
  "$POD_NAME" -- \
  sh -c "awk '/^NoNewPrivs:/ {print \$2}' /proc/1/status" \
  2>/dev/null)"

echo "NoNewPrivs: $NO_NEW_PRIVS"

if [ "$NO_NEW_PRIVS" = "1" ]; then
    echo "PASS: Privilege escalation is blocked."
else
    echo "FAIL: NoNewPrivs is not enabled."
fi

echo
echo "===== SECCOMP ====="

SECCOMP="$(kubectl exec \
  -n "$NAMESPACE" \
  "$POD_NAME" -- \
  sh -c "awk '/^Seccomp:/ {print \$2}' /proc/1/status" \
  2>/dev/null)"

echo "Seccomp mode: $SECCOMP"

if [ "$SECCOMP" = "2" ]; then
    echo "PASS: Seccomp filter mode is active."
else
    echo "INFO: Seccomp filter mode is not 2."
fi

echo
echo "===== DECLARED SECURITYCONTEXT ====="

kubectl get pod "$POD_NAME" \
  -n "$NAMESPACE" \
  -o jsonpath='PodSecurityContext={.spec.securityContext}{"\n"}ContainerSecurityContext={.spec.containers[0].securityContext}{"\n"}'

echo
echo "=================================================="
echo " VALIDATION COMPLETE"
echo "=================================================="
