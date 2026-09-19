#!/bin/bash

set +e

echo "=== Kubernetes Network Troubleshooting ==="
echo "Timestamp: $(date)"
echo

echo "=== Node Status ==="
kubectl get nodes -o wide 2>/dev/null
echo

echo "=== Pod Information ==="
kubectl get pods -o wide 2>/dev/null
echo

echo "=== Services ==="
kubectl get services -o wide 2>/dev/null
echo

echo "=== EndpointSlices ==="
kubectl get endpointslice -A 2>/dev/null
echo

SERVER_POD_IP="$(kubectl get pod server-pod \
  -o jsonpath='{.status.podIP}' \
  2>/dev/null)"

SERVICE_IP="$(kubectl get service server-service \
  -o jsonpath='{.spec.clusterIP}' \
  2>/dev/null)"

echo "=== Pod-to-Pod Connectivity ==="

if [ -n "$SERVER_POD_IP" ]; then
  echo "Server Pod IP: $SERVER_POD_IP"

  kubectl exec client-pod -- \
    ping -c 2 "$SERVER_POD_IP" \
    2>/dev/null \
    || echo "Pod ping failed"

  kubectl exec client-pod -- \
    wget -qO- \
    --timeout=5 \
    "http://$SERVER_POD_IP" \
    2>/dev/null \
    | head -5 \
    || echo "Direct Pod HTTP failed"
fi

echo
echo "=== Service Connectivity ==="

if [ -n "$SERVICE_IP" ]; then
  echo "Service ClusterIP: $SERVICE_IP"

  kubectl exec client-pod -- \
    wget -qO- \
    --timeout=5 \
    "http://$SERVICE_IP" \
    2>/dev/null \
    | head -5 \
    || echo "ClusterIP HTTP failed"
fi

echo
echo "=== Service DNS ==="

kubectl exec client-pod -- \
  nslookup server-service \
  2>/dev/null \
  || echo "Service DNS resolution failed"

echo
echo "=== Kubernetes DNS ==="

kubectl exec debug-pod -- \
  nslookup kubernetes.default.svc.cluster.local \
  2>/dev/null \
  || echo "Cluster DNS resolution failed"

echo
echo "=== Pod Resolver Configuration ==="

kubectl exec debug-pod -- \
  cat /etc/resolv.conf \
  2>/dev/null \
  || true

echo
echo "=== CoreDNS Status ==="

kubectl get pods \
  -n kube-system \
  -l k8s-app=kube-dns \
  -o wide \
  2>/dev/null

echo
echo "=== Service Backend ==="

kubectl get endpointslice \
  -l kubernetes.io/service-name=server-service \
  -o wide \
  2>/dev/null

echo
echo "=== Routing ==="

kubectl exec debug-pod -- \
  ip route show \
  2>/dev/null \
  || true

echo
echo "=== Network Troubleshooting Complete ==="
