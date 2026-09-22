#!/usr/bin/env bash
set +e

FAILURES=0

ETCDCTL="/usr/local/bin/etcdctl"

ETCD_ENDPOINT="https://127.0.0.1:2379"
ETCD_CA="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/healthcheck-client.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/healthcheck-client.key"

echo "=== Kubernetes Etcd Recovery Verification ==="
echo "Timestamp: $(date)"
echo

echo "1. Kubernetes API"
if kubectl get --raw='/readyz' >/dev/null 2>&1; then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES+1))
fi

echo
echo "2. Node readiness"
if kubectl get nodes \
  -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' \
  | grep -qx 'True'
then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES+1))
fi

echo
echo "3. Etcd endpoint health"
if sudo env ETCDCTL_API=3 \
  "$ETCDCTL" \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CA" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  endpoint health
then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES+1))
fi

echo
echo "4. backup-test namespace"
if kubectl get namespace backup-test >/dev/null 2>&1; then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES+1))
fi

echo
echo "5. nginx deployment"

READY="$(kubectl get deployment nginx-deployment \
  -n backup-test \
  -o jsonpath='{.status.readyReplicas}' \
  2>/dev/null)"

if [ "$READY" = "3" ]; then
  echo "PASS: 3/3 ready"
else
  echo "FAIL: ready replicas=${READY:-0}"
  FAILURES=$((FAILURES+1))
fi

echo
echo "6. nginx service"
if kubectl get service nginx-service \
  -n backup-test >/dev/null 2>&1
then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES+1))
fi

echo
echo "7. ConfigMap recovery marker"

EXPECTED="$(cat evidence/recovery-marker.txt 2>/dev/null)"

RESTORED="$(kubectl get configmap test-config \
  -n backup-test \
  -o jsonpath='{.data.recovery\.marker}' \
  2>/dev/null)"

if [ -n "$EXPECTED" ] && [ "$EXPECTED" = "$RESTORED" ]; then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES+1))
fi

echo
echo "8. Secret exists"
if kubectl get secret test-secret \
  -n backup-test >/dev/null 2>&1
then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES+1))
fi

echo
echo "9. Service connectivity"

if kubectl run recovery-health-client \
  -n backup-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm \
  -i \
  --command -- \
  wget -qO- --timeout=10 http://nginx-service \
  >/tmp/recovery-health-response.html 2>/dev/null
then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES+1))
fi

echo
echo "10. Static control-plane manifests"

for FILE in \
  etcd.yaml \
  kube-apiserver.yaml \
  kube-controller-manager.yaml \
  kube-scheduler.yaml
do
  if [ -f "/etc/kubernetes/manifests/$FILE" ]; then
    echo "PASS: $FILE"
  else
    echo "FAIL: $FILE"
    FAILURES=$((FAILURES+1))
  fi
done

echo
echo "========================================"

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: ALL RECOVERY CHECKS PASSED"
else
  echo "RESULT: $FAILURES CHECK(S) FAILED"
fi

echo "========================================"

exit "$FAILURES"
