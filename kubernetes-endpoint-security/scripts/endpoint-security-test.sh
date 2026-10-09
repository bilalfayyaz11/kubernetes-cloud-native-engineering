#!/usr/bin/env bash

set +e

NAMESPACE="endpoint-security"
FAILURES=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

echo "=============================================="
echo " Kubernetes Endpoint Security Validation"
echo "=============================================="

if kubectl get --raw='/readyz' >/dev/null 2>&1; then
  pass "Kubernetes API is healthy"
else
  fail "Kubernetes API health"
fi

if sudo iptables \
  -C INPUT \
  -p tcp \
  --dport 6443 \
  -j K8S_API_GUARD \
  >/dev/null 2>&1; then

  pass "API firewall chain attached"

else

  fail "API firewall chain missing"
fi

if sudo iptables \
  -C K8S_API_GUARD \
  -p tcp \
  --dport 6443 \
  -j DROP \
  >/dev/null 2>&1; then

  pass "Untrusted API traffic reaches DROP rule"

else

  fail "API default DROP rule"
fi

kubectl exec \
  -n "$NAMESPACE" \
  secure-endpoint-test \
  -- curl \
     --connect-timeout 3 \
     --max-time 5 \
     -sS \
     -o /dev/null \
     http://169.254.169.254/latest/meta-data/ \
  >/dev/null 2>&1

if [ $? -ne 0 ]; then
  pass "EC2 metadata endpoint blocked from protected workload"
else
  fail "EC2 metadata endpoint reachable"
fi

kubectl exec \
  -n "$NAMESPACE" \
  secure-endpoint-test \
  -- curl \
     --connect-timeout 3 \
     --max-time 5 \
     -sS \
     -o /dev/null \
     -X PUT \
     -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
     http://169.254.169.254/latest/api/token \
  >/dev/null 2>&1

if [ $? -ne 0 ]; then
  pass "IMDSv2 token endpoint blocked"
else
  fail "IMDSv2 token endpoint reachable"
fi

if kubectl get networkpolicy \
  restrict-sensitive-egress \
  -n "$NAMESPACE" \
  >/dev/null 2>&1; then

  pass "Metadata protection NetworkPolicy present"

else

  fail "Metadata protection NetworkPolicy missing"
fi

if kubectl exec \
  -n "$NAMESPACE" \
  secure-endpoint-test \
  -- test \
     -f /var/run/secrets/kubernetes.io/serviceaccount/token \
  >/dev/null 2>&1; then

  fail "ServiceAccount token automatically mounted"

else

  pass "Automatic ServiceAccount token disabled"
fi

UID_VALUE="$(
  kubectl exec \
    -n "$NAMESPACE" \
    secure-endpoint-test \
    -- id -u \
    2>/dev/null
)"

if [ "$UID_VALUE" = "10001" ]; then
  pass "Workload runs as non-root UID 10001"
else
  fail "Unexpected workload UID"
fi

kubectl exec \
  -n "$NAMESPACE" \
  secure-endpoint-test \
  -- sh -c \
     'touch /rootfs-test 2>/dev/null' \
  >/dev/null 2>&1

if [ $? -ne 0 ]; then
  pass "Root filesystem is read-only"
else
  fail "Root filesystem is writable"
fi

echo
echo "Failures: $FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "OVERALL RESULT: PASS"
  exit 0
else
  echo "OVERALL RESULT: FAIL"
  exit 1
fi
