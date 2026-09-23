#!/usr/bin/env bash

set +e

NAMESPACE="network-test"

SERVER_IP="$(
  kubectl get service iperf3-server-service \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.clusterIP}'
)"

SERVER_NODE="$(
  kubectl get pod iperf3-server \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.nodeName}'
)"

CLIENT_NODE="$(
  kubectl get pod iperf3-client \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.nodeName}'
)"

echo "========================================"
echo " IPERF3 CROSS-NODE PERFORMANCE TEST"
echo "========================================"
echo "Server Service IP: $SERVER_IP"
echo "Server Node: $SERVER_NODE"
echo "Client Node: $CLIENT_NODE"
echo
echo "Running 10-second TCP throughput test..."
echo

kubectl exec \
  -n "$NAMESPACE" \
  iperf3-client \
  -- iperf3 \
    -c "$SERVER_IP" \
    -t 10 \
    -f m
