#!/usr/bin/env bash
set +e

PASS_COUNT=0
FAIL_COUNT=0

DEV_WEB_IP="$(kubectl get pod web-app \
  -n development \
  -o jsonpath='{.status.podIP}')"

PROD_WEB_IP="$(kubectl get pod web-app \
  -n production \
  -o jsonpath='{.status.podIP}')"

DEV_DB_IP="$(kubectl get pod database \
  -n development \
  -o jsonpath='{.status.podIP}')"

PROD_DB_IP="$(kubectl get pod database \
  -n production \
  -o jsonpath='{.status.podIP}')"

K8S_SERVICE_IP="$(kubectl get service kubernetes \
  -n default \
  -o jsonpath='{.spec.clusterIP}')"

test_result() {

  local description="$1"
  local expected="$2"
  shift 2

  echo
  echo "TEST: $description"
  echo "Expected: $expected"

  "$@" >/tmp/netpol-test-output.txt 2>&1
  RC=$?

  if [ "$expected" = "ALLOW" ] && [ "$RC" -eq 0 ]; then
    echo "PASS: allowed as expected."
    PASS_COUNT=$((PASS_COUNT+1))

  elif [ "$expected" = "DENY" ] && [ "$RC" -ne 0 ]; then
    echo "PASS: blocked as expected."
    PASS_COUNT=$((PASS_COUNT+1))

  elif [ "$expected" = "ALLOW" ]; then
    echo "FAIL: expected ALLOW but blocked."
    cat /tmp/netpol-test-output.txt
    FAIL_COUNT=$((FAIL_COUNT+1))

  else
    echo "FAIL: expected DENY but allowed."
    cat /tmp/netpol-test-output.txt
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
}

echo "=================================================="
echo " NETWORK POLICY VALIDATION SUITE"
echo "=================================================="

echo
echo "Pod IPs:"
echo "DEV_WEB_IP=$DEV_WEB_IP"
echo "DEV_DB_IP=$DEV_DB_IP"
echo "PROD_WEB_IP=$PROD_WEB_IP"
echo "PROD_DB_IP=$PROD_DB_IP"

test_result \
  "Dev client -> Dev web:80" \
  "ALLOW" \
  kubectl exec -n development test-client -- \
  wget -qO- --timeout=5 "http://$DEV_WEB_IP"

test_result \
  "Dev web -> Dev DB:3306" \
  "ALLOW" \
  kubectl exec -n development web-app -- \
  sh -c "nc -zvw5 '$DEV_DB_IP' 3306"

test_result \
  "Dev client -> Dev DB:3306" \
  "DENY" \
  kubectl exec -n development test-client -- \
  timeout 5 nc -zvw3 "$DEV_DB_IP" 3306

test_result \
  "Dev web -> Prod DB:3306" \
  "ALLOW" \
  kubectl exec -n development web-app -- \
  sh -c "nc -zvw5 '$PROD_DB_IP' 3306"

test_result \
  "Dev client -> Prod DB:3306" \
  "DENY" \
  kubectl exec -n development test-client -- \
  timeout 5 nc -zvw3 "$PROD_DB_IP" 3306

test_result \
  "Dev client -> Prod web:80" \
  "DENY" \
  kubectl exec -n development test-client -- \
  timeout 5 wget -qO- "http://$PROD_WEB_IP"

test_result \
  "Dev web -> Prod web:80" \
  "DENY" \
  kubectl exec -n development web-app -- \
  sh -c "timeout 5 wget -qO- 'http://$PROD_WEB_IP'"

test_result \
  "Prod client -> Prod web:80" \
  "DENY" \
  kubectl exec -n production test-client -- \
  timeout 5 wget -qO- "http://$PROD_WEB_IP"

test_result \
  "Prod client -> Prod DB:3306" \
  "DENY" \
  kubectl exec -n production test-client -- \
  timeout 5 nc -zvw3 "$PROD_DB_IP" 3306

test_result \
  "Prod client -> Dev web:80" \
  "DENY" \
  kubectl exec -n production test-client -- \
  timeout 5 wget -qO- "http://$DEV_WEB_IP"

test_result \
  "Dev web DNS -> CoreDNS" \
  "ALLOW" \
  kubectl exec -n development web-app -- \
  nslookup kubernetes.default.svc.cluster.local

test_result \
  "Dev web -> Kubernetes API:443" \
  "DENY" \
  kubectl exec -n development web-app -- \
  sh -c "timeout 5 nc -zvw3 '$K8S_SERVICE_IP' 443"

echo
echo "=================================================="
echo "TEST SUMMARY"
echo "PASS: $PASS_COUNT"
echo "FAIL: $FAIL_COUNT"
echo "=================================================="

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

exit 0
