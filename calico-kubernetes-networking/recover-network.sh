#!/usr/bin/env bash

set +e

echo "=================================================="
echo " NETWORK RECOVERY PROCEDURE"
echo "=================================================="

echo
echo "===== 1. RESTART CALICO NODE PODS ====="

kubectl delete pods \
  -n calico-system \
  -l k8s-app=calico-node

echo
echo "===== 2. RESTART CALICO CONTROLLERS ====="

kubectl delete pods \
  -n calico-system \
  -l k8s-app=calico-kube-controllers

echo
echo "===== 3. WAIT FOR CALICO NODE DAEMONSET ====="

kubectl rollout status \
  daemonset/calico-node \
  -n calico-system \
  --timeout=180s

CALICO_NODE_RC=$?

if [ "$CALICO_NODE_RC" -eq 0 ]; then
  echo "PASS: calico-node recovered"
else
  echo "FAIL: calico-node recovery incomplete"
fi

echo
echo "===== 4. WAIT FOR CALICO CONTROLLERS ====="

kubectl rollout status \
  deployment/calico-kube-controllers \
  -n calico-system \
  --timeout=180s

CONTROLLER_RC=$?

if [ "$CONTROLLER_RC" -eq 0 ]; then
  echo "PASS: Calico controllers recovered"
else
  echo "FAIL: Calico controllers recovery incomplete"
fi

echo
echo "===== 5. RESTART COREDNS ====="

kubectl rollout restart \
  deployment/coredns \
  -n kube-system

echo
echo "===== 6. WAIT FOR COREDNS ====="

kubectl rollout status \
  deployment/coredns \
  -n kube-system \
  --timeout=180s

DNS_RC=$?

if [ "$DNS_RC" -eq 0 ]; then
  echo "PASS: CoreDNS recovered"
else
  echo "FAIL: CoreDNS recovery incomplete"
fi

echo
echo "===== 7. VERIFY CALICO PODS ====="

kubectl get pods \
  -n calico-system \
  -o wide

echo
echo "===== 8. VERIFY COREDNS PODS ====="

kubectl get pods \
  -n kube-system \
  -l k8s-app=kube-dns \
  -o wide

echo
echo "===== 9. VERIFY TEST PODS ====="

kubectl get pods \
  -n network-test \
  -o wide

echo
echo "===== 10. VERIFY CROSS-NODE CONNECTIVITY ====="

POD1_IP="$(
  kubectl get pod test-pod-1 \
    -n network-test \
    -o jsonpath='{.status.podIP}'
)"

POD2_IP="$(
  kubectl get pod test-pod-2 \
    -n network-test \
    -o jsonpath='{.status.podIP}'
)"

RC1=1
RC2=1

if [ -n "$POD1_IP" ] && [ -n "$POD2_IP" ]; then
  kubectl exec \
    -n network-test \
    test-pod-1 \
    -- ping -c 3 "$POD2_IP"

  RC1=$?

  kubectl exec \
    -n network-test \
    test-pod-2 \
    -- ping -c 3 "$POD1_IP"

  RC2=$?
fi

if [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ]; then
  echo "Network recovery verified: connectivity restored."
else
  echo "Recovery check failed: connectivity still broken."
fi

echo
echo "===== 11. VERIFY DNS ====="

kubectl run recovery-dns-check \
  --namespace network-test \
  --image=busybox:1.37 \
  --restart=Never \
  --rm \
  -i \
  -- nslookup kubernetes.default.svc.cluster.local \
  2>/dev/null

DNS_TEST_RC=$?

if [ "$DNS_TEST_RC" -eq 0 ]; then
  echo "PASS: DNS resolution working"
else
  echo "WARNING: DNS validation failed"
fi

echo
echo "===== 12. FINAL NODE STATE ====="

kubectl get nodes -o wide

echo
echo "=================================================="
echo " NETWORK RECOVERY PROCEDURE COMPLETE"
echo "=================================================="
