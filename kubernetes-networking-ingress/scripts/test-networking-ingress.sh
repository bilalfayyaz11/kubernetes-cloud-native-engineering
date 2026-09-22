#!/usr/bin/env bash
set +e

FAILURES=0

NODE_IP="$(kubectl get node \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
  2>/dev/null)"

HTTP_NODEPORT="$(kubectl get service ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' \
  2>/dev/null)"

HTTPS_NODEPORT="$(kubectl get service ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' \
  2>/dev/null)"

echo "=== Kubernetes Networking and Ingress Test ==="
echo "Timestamp: $(date)"
echo
echo "Node IP:        ${NODE_IP:-unknown}"
echo "HTTP NodePort:  ${HTTP_NODEPORT:-unknown}"
echo "HTTPS NodePort: ${HTTPS_NODEPORT:-unknown}"
echo

echo "1. LoadBalancer Service"
kubectl get service web-app-loadbalancer -o wide || FAILURES=$((FAILURES+1))
echo

echo "2. Web Backend Deployment"
kubectl get deployment web-app || FAILURES=$((FAILURES+1))
echo

echo "3. API Backend Deployment"
kubectl get deployment api-app || FAILURES=$((FAILURES+1))
echo

echo "4. Backend Services"
kubectl get service web-app-service api-app-service || FAILURES=$((FAILURES+1))
echo

echo "5. Web EndpointSlice"
kubectl get endpointslice \
  -l kubernetes.io/service-name=web-app-service \
  -o wide || FAILURES=$((FAILURES+1))
echo

echo "6. API EndpointSlice"
kubectl get endpointslice \
  -l kubernetes.io/service-name=api-app-service \
  -o wide || FAILURES=$((FAILURES+1))
echo

echo "7. Ingress Resource"
kubectl get ingress web-app-ingress -o wide || FAILURES=$((FAILURES+1))
echo

echo "8. TLS Secret"
kubectl get secret networking-tls || FAILURES=$((FAILURES+1))
echo

echo "9. HTTPS Root Route"

ROOT_BODY="$(curl \
  -k \
  -fsS \
  --connect-timeout 10 \
  -H 'Host: networking.local' \
  "https://${NODE_IP}:${HTTPS_NODEPORT}/" \
  2>/dev/null)"

if echo "$ROOT_BODY" | grep -q 'Kubernetes Networking'; then
  echo "PASS: / -> web-app-service"
else
  echo "FAIL: root HTTPS routing"
  FAILURES=$((FAILURES+1))
fi

echo
echo "10. HTTPS API Route"

API_BODY="$(curl \
  -k \
  -fsS \
  --connect-timeout 10 \
  -H 'Host: networking.local' \
  "https://${NODE_IP}:${HTTPS_NODEPORT}/api/" \
  2>/dev/null)"

if echo "$API_BODY" | grep -q 'Backend API'; then
  echo "PASS: /api -> api-app-service"
else
  echo "FAIL: HTTPS /api routing"
  FAILURES=$((FAILURES+1))
fi

echo
echo "11. HTTP -> HTTPS Redirect"

STATUS="$(curl \
  -sS \
  -o /dev/null \
  -w '%{http_code}' \
  -H 'Host: networking.local' \
  "http://${NODE_IP}:${HTTP_NODEPORT}/" \
  2>/dev/null)"

echo "HTTP status: $STATUS"

case "$STATUS" in
  301|302|307|308)
    echo "PASS: redirect response observed"
    ;;
  *)
    echo "FAIL: expected HTTP redirect"
    FAILURES=$((FAILURES+1))
    ;;
esac

echo
echo "12. Served Certificate"

CERT_INFO="$(echo \
  | openssl s_client \
      -connect "${NODE_IP}:${HTTPS_NODEPORT}" \
      -servername networking.local \
      2>/dev/null \
  | openssl x509 \
      -noout \
      -subject \
      -issuer \
      -dates \
      -ext subjectAltName \
      2>/dev/null)"

echo "$CERT_INFO"

if echo "$CERT_INFO" | grep -q 'networking.local'; then
  echo "PASS: certificate hostname verified"
else
  echo "FAIL: certificate hostname verification"
  FAILURES=$((FAILURES+1))
fi

echo
echo "13. Ingress Controller"

kubectl get deployment ingress-nginx-controller \
  -n ingress-nginx || FAILURES=$((FAILURES+1))

echo
echo "14. IngressClass"

kubectl get ingressclass nginx || FAILURES=$((FAILURES+1))

echo
echo "15. Warning Events"

kubectl get events \
  -A \
  --field-selector type=Warning \
  --sort-by=.metadata.creationTimestamp \
  2>/dev/null \
  | tail -15 || true

echo
echo "========================================"

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: ALL NETWORKING CHECKS PASSED"
else
  echo "RESULT: $FAILURES CHECK(S) FAILED"
fi

echo "========================================"

exit "$FAILURES"
