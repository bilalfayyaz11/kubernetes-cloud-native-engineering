#!/usr/bin/env bash

set -u

PASS=0
FAIL=0
WARN=0

pass() {
    echo "✅ $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "❌ $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo "⚠️  $1"
    WARN=$((WARN + 1))
}

echo "============================================================"
echo " Kubernetes API Server Security Verification"
echo "============================================================"
echo

echo "1. API Server Readiness"
echo "------------------------------------------------------------"

if kubectl get --raw='/readyz' 2>/dev/null | grep -q '^ok$'; then
    pass "API server readiness endpoint reports OK"
else
    fail "API server readiness check failed"
fi

echo
echo "2. RBAC Least-Privilege Verification"
echo "------------------------------------------------------------"

ALLOWED_READ="$(
    kubectl auth can-i get pods \
      --as=testuser \
      -n security-lab \
      2>/dev/null
)"

DENIED_DELETE="$(
    kubectl auth can-i delete pods \
      --as=testuser \
      -n security-lab \
      2>/dev/null
)"

DENIED_DEFAULT="$(
    kubectl auth can-i get pods \
      --as=testuser \
      -n default \
      2>/dev/null
)"

DENIED_CREATE="$(
    kubectl auth can-i create deployments.apps \
      --as=testuser \
      -n security-lab \
      2>/dev/null
)"

if [ "$ALLOWED_READ" = "yes" ]; then
    pass "testuser can read pods in security-lab"
else
    fail "testuser cannot perform intended pod read"
fi

if [ "$DENIED_DELETE" = "no" ]; then
    pass "testuser cannot delete pods"
else
    fail "testuser can unexpectedly delete pods"
fi

if [ "$DENIED_DEFAULT" = "no" ]; then
    pass "testuser cannot read pods in default namespace"
else
    fail "testuser has unexpected cross-namespace access"
fi

if [ "$DENIED_CREATE" = "no" ]; then
    pass "testuser cannot create deployments"
else
    fail "testuser has unexpected deployment creation rights"
fi

echo
echo "3. Client Certificate Authentication"
echo "------------------------------------------------------------"

if kubectl \
    --kubeconfig=testuser-kubeconfig.yaml \
    auth whoami \
    >/tmp/testuser-whoami.txt 2>/dev/null; then

    cat /tmp/testuser-whoami.txt
    pass "testuser authenticates with an X.509 client certificate"
else
    fail "testuser client-certificate authentication failed"
fi

rm -f /tmp/testuser-whoami.txt

echo
echo "4. Encryption Provider Configuration"
echo "------------------------------------------------------------"

if sudo grep -q -- \
    '--encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml' \
    /etc/kubernetes/manifests/kube-apiserver.yaml; then

    pass "API server uses encryption-provider-config"
else
    fail "API server encryption-provider flag is missing"
fi

if sudo test -f /etc/kubernetes/enc/encryption-config.yaml; then
    pass "Encryption configuration file exists"
else
    fail "Encryption configuration file is missing"
fi

if sudo python3 - <<'PY'
import base64
import yaml
import sys

path = "/etc/kubernetes/enc/encryption-config.yaml"

try:
    with open(path) as f:
        data = yaml.safe_load(f)

    entry = data["resources"][0]

    resources = entry["resources"]
    providers = entry["providers"]

    assert "secrets" in resources
    assert "configmaps" in resources
    assert "aescbc" in providers[0]
    assert "identity" in providers[1]

    secret = providers[0]["aescbc"]["keys"][0]["secret"]
    assert len(base64.b64decode(secret)) == 32

except Exception as exc:
    print(exc)
    sys.exit(1)
PY
then
    pass "EncryptionConfiguration structure and AES-256 key are valid"
else
    fail "EncryptionConfiguration validation failed"
fi

echo
echo "5. Create Fresh Encryption Test Secret"
echo "------------------------------------------------------------"

kubectl delete secret encryption-test \
    -n security-lab \
    --ignore-not-found \
    >/dev/null 2>&1

if kubectl create secret generic encryption-test \
    --from-literal=data=sensitive-information \
    -n security-lab \
    >/dev/null; then

    pass "Fresh test Secret created"
else
    fail "Unable to create encryption test Secret"
fi

echo
echo "6. Direct etcd Encryption Verification"
echo "------------------------------------------------------------"

ETCD_FILE="$(mktemp)"

if sudo ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt \
    --key=/etc/kubernetes/pki/apiserver-etcd-client.key \
    get /registry/secrets/security-lab/encryption-test \
    > "$ETCD_FILE" 2>/dev/null; then

    pass "Raw Secret record retrieved directly from etcd"
else
    fail "Unable to read raw Secret record from etcd"
fi

if grep -a -q 'sensitive-information' "$ETCD_FILE"; then
    fail "Plaintext secret value is visible in etcd"
else
    pass "Plaintext secret value is not visible in etcd"
fi

if strings "$ETCD_FILE" \
    | grep -q 'k8s:enc:aescbc:v1:key1'; then

    pass "Kubernetes AES-CBC encryption marker detected in etcd"
else
    warn "AES-CBC marker not visible through strings output"
fi

rm -f "$ETCD_FILE"

echo
echo "7. Verify API Can Decrypt Stored Secret"
echo "------------------------------------------------------------"

DECRYPTED="$(
    kubectl get secret encryption-test \
      -n security-lab \
      -o jsonpath='{.data.data}' \
      2>/dev/null \
      | base64 -d
)"

if [ "$DECRYPTED" = "sensitive-information" ]; then
    pass "API server successfully decrypts encrypted Secret"
else
    fail "Secret could not be correctly decrypted through Kubernetes API"
fi

echo
echo "8. API Server TLS Certificate Validation"
echo "------------------------------------------------------------"

if sudo openssl verify \
    -CAfile /etc/kubernetes/pki/ca.crt \
    /etc/kubernetes/pki/apiserver.crt \
    >/dev/null 2>&1; then

    pass "API server certificate chains to Kubernetes CA"
else
    fail "API server certificate verification failed"
fi

echo
sudo openssl x509 \
    -in /etc/kubernetes/pki/apiserver.crt \
    -noout \
    -subject \
    -issuer \
    -dates

echo
echo "9. API Server SAN Validation"
echo "------------------------------------------------------------"

SAN_OUTPUT="$(
    sudo openssl x509 \
      -in /etc/kubernetes/pki/apiserver.crt \
      -noout \
      -ext subjectAltName \
      2>/dev/null
)"

echo "$SAN_OUTPUT"

if printf '%s' "$SAN_OUTPUT" \
    | grep -q 'kubernetes.default.svc'; then

    pass "Expected Kubernetes service DNS SAN is present"
else
    fail "Expected Kubernetes API DNS SAN is missing"
fi

echo
echo "10. Certificate Expiration"
echo "------------------------------------------------------------"

if sudo openssl x509 \
    -in /etc/kubernetes/pki/apiserver.crt \
    -noout \
    -checkend $((30 * 86400)) \
    >/dev/null 2>&1; then

    pass "API server certificate is valid for more than 30 days"
else
    warn "API server certificate expires within 30 days"
fi

echo
echo "11. kubeadm Certificate Health"
echo "------------------------------------------------------------"

if sudo kubeadm certs check-expiration; then
    pass "kubeadm certificate expiration check completed"
else
    warn "kubeadm certificate expiration check reported an issue"
fi

echo
echo "12. API Server Security Flags"
echo "------------------------------------------------------------"

sudo grep -E -- \
    '--authorization-mode|--client-ca-file|--tls-cert-file|--tls-private-key-file|--encryption-provider-config' \
    /etc/kubernetes/manifests/kube-apiserver.yaml \
    || true

if sudo grep -q -- '--authorization-mode=.*RBAC' \
    /etc/kubernetes/manifests/kube-apiserver.yaml; then

    pass "RBAC authorization is enabled"
else
    fail "RBAC authorization mode was not detected"
fi

if sudo grep -q -- '--client-ca-file=' \
    /etc/kubernetes/manifests/kube-apiserver.yaml; then

    pass "Client certificate CA is configured"
else
    fail "API server client CA configuration is missing"
fi

echo
echo "============================================================"
echo " Final Security Verification Summary"
echo "============================================================"
echo "PASS : $PASS"
echo "WARN : $WARN"
echo "FAIL : $FAIL"

echo

if [ "$FAIL" -gt 0 ]; then
    echo "Overall Status: FAILED"
    exit 1
fi

echo "Overall Status: PASSED"
exit 0
