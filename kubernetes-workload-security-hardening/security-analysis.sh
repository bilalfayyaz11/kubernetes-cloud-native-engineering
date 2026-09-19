#!/usr/bin/env bash
set +e

echo "=================================================="
echo " SECURITY ANALYSIS REPORT"
echo "=================================================="

for pod in \
  basic-pod \
  restricted-pod \
  secure-webapp \
  netadmin-pod \
  no-netadmin-pod
do
    echo
    echo "--------------------------------------------------"
    echo "Pod: $pod"
    echo "--------------------------------------------------"

    if ! kubectl get pod "$pod" >/dev/null 2>&1; then
        echo "Pod not found."
        continue
    fi

    USER_ID="$(kubectl exec "$pod" -- id -u 2>/dev/null || echo N/A)"
    GROUP_ID="$(kubectl exec "$pod" -- id -g 2>/dev/null || echo N/A)"

    CAP_EFF="$(kubectl exec "$pod" -- \
      sh -c "awk '/^CapEff:/ {print \$2}' /proc/1/status" \
      2>/dev/null || echo N/A)"

    NO_NEW_PRIVS="$(kubectl exec "$pod" -- \
      sh -c "awk '/^NoNewPrivs:/ {print \$2}' /proc/1/status" \
      2>/dev/null || echo N/A)"

    SECCOMP="$(kubectl exec "$pod" -- \
      sh -c "awk '/^Seccomp:/ {print \$2}' /proc/1/status" \
      2>/dev/null || echo N/A)"

    if kubectl exec "$pod" -- \
      touch /security-analysis-root-write \
      >/dev/null 2>&1
    then
        ROOT_WRITABLE="YES"

        kubectl exec "$pod" -- \
          rm -f /security-analysis-root-write \
          >/dev/null 2>&1 || true
    else
        ROOT_WRITABLE="NO"
    fi

    echo "UID                : $USER_ID"
    echo "GID                : $GROUP_ID"
    echo "Root FS writable   : $ROOT_WRITABLE"
    echo "CapEff             : $CAP_EFF"
    echo "NoNewPrivs         : $NO_NEW_PRIVS"
    echo "Seccomp mode       : $SECCOMP"
done

echo
echo "=================================================="
echo " SECURITY ANALYSIS COMPLETE"
echo "=================================================="
