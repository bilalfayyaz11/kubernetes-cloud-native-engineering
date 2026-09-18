#!/usr/bin/env bash

set +e

NAMESPACE="ingress-networking"
HTTPS_LOCAL_PORT="9443"

PASS_COUNT=0
FAIL_COUNT=0

record_result() {
  NAME="$1"
  STATUS="$2"
  DETAIL="$3"

  if [ "$STATUS" = "PASS" ]; then
    echo "PASS | $NAME | $DETAIL"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL | $NAME | $DETAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "=== Kubernetes Networking Validation ==="
echo

NODEPORT_URL="$(
  minikube service \
    web-app-nodeport \
    -n "$NAMESPACE" \
    --url \
    2>/dev/null \
    | head -n 1
)"

if [ -n "$NODEPORT_URL" ]; then

  NODEPORT_CODE="$(
    curl \
      --connect-timeout 5 \
      --max-time 10 \
      -s \
      -o /dev/null \
      -w '%{http_code}' \
      "$NODEPORT_URL" \
      2>/dev/null
  )"

  if [ "$NODEPORT_CODE" = "200" ]; then
    record_result "NodePort" "PASS" "HTTP $NODEPORT_CODE"
  else
    record_result "NodePort" "FAIL" "HTTP ${NODEPORT_CODE:-unavailable}"
  fi

else

  record_result "NodePort" "FAIL" "No Minikube service URL"

fi

HTTP_CODE="$(
  curl \
    --connect-timeout 5 \
    --max-time 10 \
    -s \
    -o /dev/null \
    -w '%{http_code}' \
    -H 'Host: webapp.local' \
    http://127.0.0.1:8080/ \
    2>/dev/null
)"

case "$HTTP_CODE" in
  200|301|302|307|308)
    record_result "HTTP Ingress" "PASS" "HTTP $HTTP_CODE"
    ;;
  *)
    record_result "HTTP Ingress" "FAIL" "HTTP ${HTTP_CODE:-unavailable}"
    ;;
esac

HTTPS_CODE="$(
  curl \
    -k \
    --connect-timeout 5 \
    --max-time 10 \
    -s \
    -o /dev/null \
    -w '%{http_code}' \
    --resolve "webapp.local:${HTTPS_LOCAL_PORT}:127.0.0.1" \
    "https://webapp.local:${HTTPS_LOCAL_PORT}/" \
    2>/dev/null
)"

if [ "$HTTPS_CODE" = "200" ]; then
  record_result "HTTPS Ingress" "PASS" "HTTP $HTTPS_CODE"
else
  record_result "HTTPS Ingress" "FAIL" "HTTP ${HTTPS_CODE:-unavailable}"
fi

CERT_SUBJECT="$(
  echo \
    | openssl s_client \
        -connect "127.0.0.1:${HTTPS_LOCAL_PORT}" \
        -servername webapp.local \
        2>/dev/null \
    | openssl x509 \
        -noout \
        -subject \
        2>/dev/null
)"

if echo "$CERT_SUBJECT" | grep -q 'webapp.local'; then
  record_result "TLS Certificate" "PASS" "$CERT_SUBJECT"
else
  record_result "TLS Certificate" "FAIL" "${CERT_SUBJECT:-certificate unavailable}"
fi

READY_ENDPOINTS="$(
  kubectl get endpointslice \
    -n "$NAMESPACE" \
    -l kubernetes.io/service-name=web-app-service \
    -o json \
    2>/dev/null \
  | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length'
)"

if [ "${READY_ENDPOINTS:-0}" -ge 3 ]; then
  record_result "Backend Endpoints" "PASS" "${READY_ENDPOINTS} ready endpoints"
else
  record_result "Backend Endpoints" "FAIL" "${READY_ENDPOINTS:-0} ready endpoints"
fi

echo
echo "=== Result Summary ==="
echo "PASS: $PASS_COUNT"
echo "FAIL: $FAIL_COUNT"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "OVERALL: PASS"
else
  echo "OVERALL: REVIEW"
fi
