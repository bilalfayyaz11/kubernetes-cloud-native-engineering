#!/usr/bin/env bash

set +e

echo "=================================================="
echo " KUBERNETES NETWORK TROUBLESHOOTING REPORT"
echo "=================================================="
echo "Timestamp: $(date -Is)"

echo
echo "===== 1. NODE STATUS ====="
kubectl get nodes -o wide

echo
echo "===== 2. CALICO SYSTEM PODS ====="
kubectl get pods -n calico-system -o wide

echo
echo "===== 3. CALICO DAEMONSET ====="
kubectl get daemonset calico-node \
  -n calico-system \
  -o wide

echo
echo "===== 4. CALICO CONTROLLERS ====="
kubectl get deployment calico-kube-controllers \
  -n calico-system \
  -o wide

echo
echo "===== 5. TEST NAMESPACE PODS ====="
kubectl get pods \
  -n network-test \
  -o wide

echo
echo "===== 6. CALICO IP POOLS ====="
kubectl get ippools.crd.projectcalico.org \
  -o custom-columns='NAME:.metadata.name,CIDR:.spec.cidr,VXLAN:.spec.vxlanMode,NAT:.spec.natOutgoing' \
  2>/dev/null || true

echo
echo "===== 7. NETWORK POLICIES ====="
kubectl get networkpolicies \
  --all-namespaces \
  2>/dev/null || true

echo
echo "===== 8. NODE ROUTING ====="

for node in $(kind get nodes --name calico-network); do
  echo
  echo "--- $node ---"

  docker exec "$node" ip route show \
    2>/dev/null || true
done

echo
echo "===== 9. VXLAN INTERFACES ====="

for node in $(kind get nodes --name calico-network); do
  echo
  echo "--- $node ---"

  docker exec "$node" \
    ip -d link show vxlan.calico \
    2>/dev/null \
    || echo "vxlan.calico not present"
done

echo
echo "===== 10. CNI CONFIGURATION ====="

for node in $(kind get nodes --name calico-network); do
  echo
  echo "--- $node ---"

  docker exec "$node" sh -c '
    ls -la /etc/cni/net.d 2>/dev/null || true

    if [ -f /etc/cni/net.d/10-calico.conflist ]; then
      cat /etc/cni/net.d/10-calico.conflist
    else
      echo "10-calico.conflist missing"
    fi
  '
done

echo
echo "===== 11. CALICO NODE LOGS ====="

for pod in $(
  kubectl get pods \
    -n calico-system \
    -l k8s-app=calico-node \
    -o jsonpath='{.items[*].metadata.name}'
); do
  echo
  echo "--- $pod ---"

  kubectl logs \
    -n calico-system \
    "$pod" \
    -c calico-node \
    --tail=40 \
    2>/dev/null || true
done

echo
echo "===== 12. COREDNS STATUS ====="

kubectl get pods \
  -n kube-system \
  -l k8s-app=kube-dns \
  -o wide

echo
echo "===== 13. DNS RESOLUTION TEST ====="

kubectl run dns-check \
  --namespace network-test \
  --image=busybox:1.37 \
  --restart=Never \
  --rm \
  -i \
  -- nslookup kubernetes.default.svc.cluster.local \
  2>/dev/null || true

echo
echo "=================================================="
echo " END OF NETWORK TROUBLESHOOTING REPORT"
echo "=================================================="
