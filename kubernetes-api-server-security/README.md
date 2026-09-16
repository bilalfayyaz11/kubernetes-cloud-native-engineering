# Kubernetes API Server Security Hardening

## What This Does

This implementation secures a Kubernetes control plane through three critical layers: least-privilege authorization, encryption at rest, and authenticated TLS communication.

A restricted client identity is issued through the Kubernetes CSR API and bound to namespace-scoped RBAC permissions. Sensitive Kubernetes resources are encrypted before being persisted to etcd using an API-server encryption provider configuration. The API server's TLS certificates, client authentication path, certificate chain, Subject Alternative Names, and expiry state are then validated.

The result is a reproducible Kubernetes API security baseline that demonstrates control-plane hardening rather than only workload-level security.

## Architecture

    +------------------------------------------------------------------+
    |                    Kubernetes API Security                        |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                    CLIENT AUTHENTICATION                          |
    |                                                                  |
    |  testuser                                                        |
    |     |                                                            |
    |     +--> Private Key                                             |
    |     +--> Certificate Signing Request                             |
    |     +--> Kubernetes CSR Approval                                 |
    |     +--> Client Certificate                                      |
    |                                                                  |
    |                  X.509 Authentication                             |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                       API SERVER                                  |
    |                                                                  |
    |  TLS                                                             |
    |    +--> Cluster CA                                                |
    |    +--> API Server Certificate                                   |
    |    +--> Subject Alternative Names                                |
    |                                                                  |
    |  Authorization                                                   |
    |    +--> RBAC                                                     |
    |    +--> Namespace-Scoped Role                                    |
    |    +--> RoleBinding                                              |
    |                                                                  |
    |  Encryption                                                      |
    |    +--> EncryptionConfiguration                                  |
    |    +--> AES-CBC Provider                                         |
    |    +--> Identity Fallback                                        |
    +------------------------------------------------------------------+
                     |                         |
                     |                         |
                     v                         v
    +-------------------------------+   +------------------------------+
    |        RBAC DECISIONS         |   |        DATA STORAGE          |
    |                               |   |                              |
    |  security-lab                 |   |  Kubernetes API              |
    |    get/list pods     ALLOW    |   |       |                      |
    |    get pod logs      ALLOW    |   |       v                      |
    |    delete pods       DENY     |   |  Encryption Provider         |
    |    create deploy     DENY     |   |       |                      |
    |                               |   |       v                      |
    |  default namespace   DENY     |   |     etcd                     |
    +-------------------------------+   |       |                      |
                                        |   Encrypted Secret Data      |
                                        +------------------------------+
                                                       |
                                                       v
    +------------------------------------------------------------------+
    |                       VERIFICATION                                |
    |                                                                  |
    |  kubectl auth can-i                                               |
    |  Client certificate authentication                               |
    |  Direct HTTPS API access                                         |
    |  Direct etcd ciphertext inspection                               |
    |  OpenSSL certificate validation                                  |
    |  kubeadm certificate expiry check                                |
    |  Automated API security verification                             |
    +------------------------------------------------------------------+

## Prerequisites

- Ubuntu Linux
- sudo privileges
- containerd
- kubeadm
- kubelet
- kubectl
- etcdctl
- OpenSSL
- Python 3
- PyYAML
- jq
- curl
- Bash
- A kubeadm-managed Kubernetes control plane
- Direct host access to Kubernetes static pod manifests and PKI

Expected Kubernetes control-plane paths:

    /etc/kubernetes/manifests/
    /etc/kubernetes/pki/
    /etc/kubernetes/pki/etcd/

## Environment Preparation

Disable swap:

    sudo swapoff -a

Load required kernel modules:

    sudo modprobe overlay
    sudo modprobe br_netfilter

Required sysctl values:

    net.bridge.bridge-nf-call-iptables=1
    net.bridge.bridge-nf-call-ip6tables=1
    net.ipv4.ip_forward=1

Configure containerd with the systemd cgroup driver.

Initialize the Kubernetes control plane:

    sudo kubeadm init --pod-network-cidr=10.244.0.0/16

Configure kubectl:

    mkdir -p ~/.kube
    sudo cp /etc/kubernetes/admin.conf ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config

Install a compatible CNI implementation and verify:

    kubectl get nodes
    kubectl get pods -n kube-system

## How to Reproduce

### 1. Create a Restricted Kubernetes Identity

Create an isolated namespace:

    kubectl create namespace security-lab

Generate a private key:

    openssl genrsa -out testuser.key 2048

Create a certificate signing request:

    openssl req \
      -new \
      -key testuser.key \
      -out testuser.csr \
      -subj "/CN=testuser/O=developers"

Create a Kubernetes CertificateSigningRequest resource using the signer:

    kubernetes.io/kube-apiserver-client

Approve it:

    kubectl certificate approve testuser-csr

Extract the signed certificate:

    kubectl get csr testuser-csr \
      -o jsonpath='{.status.certificate}' \
      | base64 -d \
      > testuser.crt

### 2. Configure Least-Privilege RBAC

Create a namespace-scoped Role granting only:

- `get` pods
- `list` pods
- `get` pod logs

Apply:

    kubectl apply -f pod-reader-role.yaml
    kubectl apply -f read-pods-rolebinding.yaml

The RoleBinding maps the X.509 identity:

    testuser

to the restricted Role inside:

    security-lab

### 3. Validate RBAC Boundaries

Allowed operation:

    kubectl auth can-i get pods \
      --as=testuser \
      -n security-lab

Expected:

    yes

Denied operations:

    kubectl auth can-i delete pods \
      --as=testuser \
      -n security-lab

    kubectl auth can-i create deployments.apps \
      --as=testuser \
      -n security-lab

    kubectl auth can-i get pods \
      --as=testuser \
      -n default

Expected:

    no
    no
    no

This demonstrates both least privilege and namespace isolation.

### 4. Enable Encryption at Rest

Create the encryption configuration:

    /etc/kubernetes/enc/encryption-config.yaml

The configuration protects:

- Secrets
- ConfigMaps

Primary provider:

    aescbc

Fallback provider:

    identity

The primary encryption key is a randomly generated 32-byte AES key.

### 5. Modify the API Server Safely

Back up the static pod manifest outside the static-pod directory:

    /etc/kubernetes/backup/

Do not store backup manifests inside:

    /etc/kubernetes/manifests/

Add the API-server argument:

    --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml

Mount the encryption configuration into the API-server static pod.

The kubelet automatically detects the static pod manifest change and restarts the API server.

Verify readiness:

    kubectl get --raw='/readyz'

Expected:

    ok

### 6. Verify Encryption Directly in etcd

Create a Secret:

    kubectl create secret generic test-secret \
      --from-literal=password=supersecret \
      -n security-lab

Read the underlying etcd record using:

    etcdctl

with the kubeadm-generated etcd CA and API-server etcd client certificate.

Expected result:

- Plaintext value is not visible
- Kubernetes encryption metadata identifies the configured encryption provider
- The API server can still decrypt the resource transparently

### 7. Re-Encrypt Existing Resources

Enabling encryption only affects subsequent writes.

Rewrite Secrets:

    kubectl get secrets \
      --all-namespaces \
      -o json \
      | kubectl replace -f -

Rewrite ConfigMaps:

    kubectl get configmaps \
      --all-namespaces \
      -o json \
      | kubectl replace -f -

This migrates previously stored objects through the active encryption provider.

## TLS and PKI Validation

### 8. Inspect the Live API Server Certificate

Inspect identity and validity:

    sudo openssl x509 \
      -in /etc/kubernetes/pki/apiserver.crt \
      -noout \
      -subject \
      -issuer \
      -serial \
      -dates \
      -fingerprint \
      -sha256

Inspect SANs:

    sudo openssl x509 \
      -in /etc/kubernetes/pki/apiserver.crt \
      -noout \
      -ext subjectAltName

Verify the certificate chain:

    sudo openssl verify \
      -CAfile /etc/kubernetes/pki/ca.crt \
      /etc/kubernetes/pki/apiserver.crt

Expected:

    /etc/kubernetes/pki/apiserver.crt: OK

### 9. Generate a Separate PKI Chain

A separate demonstration CA was created to practice PKI operations without modifying the live Kubernetes trust chain.

Generated components:

- Root CA private key
- Root CA certificate
- API-server-style private key
- Server certificate signing request
- SAN-enabled server certificate
- Client private key
- Client certificate signing request
- Client authentication certificate

The server certificate includes:

- `serverAuth`
- Kubernetes service DNS SANs
- localhost
- Kubernetes service IP

The client certificate includes:

    clientAuth

The chains are validated locally with:

    openssl verify

This PKI remains deliberately independent from the live Kubernetes cluster CA.

### 10. Validate Real Client Certificate Authentication

The Kubernetes-issued `testuser` certificate is used for live authentication.

Create a dedicated kubeconfig using:

- Cluster CA
- `testuser.crt`
- `testuser.key`
- API-server endpoint

Verify identity:

    kubectl \
      --kubeconfig=testuser-kubeconfig.yaml \
      auth whoami

Verify allowed access:

    kubectl \
      --kubeconfig=testuser-kubeconfig.yaml \
      get pods \
      -n security-lab

Verify denied access:

    kubectl \
      --kubeconfig=testuser-kubeconfig.yaml \
      get pods \
      -n default

### 11. Validate Direct HTTPS API Access

Use curl with mutual TLS:

    curl \
      --cacert kubernetes-ca.crt \
      --cert testuser.crt \
      --key testuser.key \
      https://API-SERVER/api/v1/namespaces/security-lab/pods

Expected:

- TLS certificate verification succeeds
- Client certificate authentication succeeds
- RBAC authorizes access

Requesting:

    /api/v1/namespaces/default/pods

should return:

    HTTP 403

This proves authentication succeeded but authorization denied access.

## Certificate Health Monitoring

### 12. Check kubeadm-Managed Certificate Expiry

Run:

    sudo kubeadm certs check-expiration

This displays expiration information for Kubernetes control-plane certificates.

### 13. Run Automated Certificate Monitoring

Execute:

    ./check-cert-expiry.sh

The script examines certificates in:

    /etc/kubernetes/pki/*.crt
    /etc/kubernetes/pki/etcd/*.crt

It reports:

- Subject
- Expiration date
- Whether the certificate expires within 30 days

## Comprehensive Security Validation

Run:

    ./security-test.sh

The validation script checks:

- API-server readiness
- RBAC allowed operations
- RBAC denied operations
- Cross-namespace isolation
- X.509 client authentication
- Encryption provider configuration
- AES-256 encryption key structure
- Direct etcd storage behavior
- Plaintext absence in etcd
- API-server decryption
- TLS certificate chain validation
- Subject Alternative Names
- Certificate expiry
- kubeadm certificate health
- API-server RBAC configuration
- Client CA configuration

A secure result should finish with:

    FAIL : 0
    Overall Status: PASSED

## Tools Used

- Kubernetes
- kubeadm
- kubelet
- kubectl
- containerd
- etcd
- etcdctl
- OpenSSL
- Kubernetes RBAC
- Kubernetes CSR API
- X.509 certificates
- PKI
- AES-CBC encryption provider
- TLS
- Bash
- jq
- Python
- PyYAML
- curl

## Key Skills Demonstrated

- Kubernetes API-server hardening
- Kubernetes control-plane administration
- Least-privilege RBAC design
- Namespace-scoped authorization
- X.509 client authentication
- Kubernetes CSR workflows
- Public key infrastructure
- TLS certificate inspection
- Certificate-chain verification
- Subject Alternative Name validation
- Encryption-at-rest configuration
- etcd security
- Sensitive-data protection
- Static pod administration
- kubeadm certificate management
- Certificate expiry monitoring
- Kubernetes security testing
- Control-plane troubleshooting
- Secure configuration migration
- Automated compliance validation

## Real-World Use Case

A platform engineering or DevSecOps team can use these controls to protect production Kubernetes control planes.

RBAC restricts engineers, service identities, and automated systems to only the resources they require. X.509 client authentication provides cryptographically verifiable identities for API access. TLS protects data in transit between clients and the Kubernetes API server.

Encryption at rest adds another security boundary by ensuring Kubernetes Secrets and other selected resources are encrypted before they are persisted into etcd. This reduces exposure if an attacker obtains access to raw etcd storage or backups.

Certificate monitoring helps prevent API outages caused by expired control-plane certificates, while automated validation verifies that security controls remain active after configuration changes.

## Security Controls Implemented

### Authentication

- Kubernetes-issued X.509 client certificate
- Dedicated restricted user identity
- Trusted Kubernetes client CA
- Mutual TLS API access

### Authorization

- Kubernetes RBAC
- Namespace-scoped Role
- Namespace-scoped RoleBinding
- Explicit permission testing
- Cross-namespace access denial

### Data Protection

- Kubernetes EncryptionConfiguration
- AES-256 encryption key
- Encryption of Secrets
- Encryption of ConfigMaps
- Direct etcd ciphertext validation
- Migration of existing resources

### Transport Security

- Kubernetes API-server TLS
- Cluster CA validation
- API-server certificate verification
- SAN validation
- TLS handshake verification

### Certificate Management

- Custom CA generation
- Server certificate generation
- Client certificate generation
- Extended Key Usage configuration
- Certificate-chain validation
- Certificate expiry monitoring
- kubeadm certificate health checks

### Security Validation

- API readiness testing
- RBAC behavior verification
- Direct client-certificate authentication
- Direct HTTPS API testing
- Direct etcd inspection
- Encryption validation
- Automated control-plane security testing

## Lessons Learned

- Kubernetes API access is a combination of authentication and authorization; successful X.509 authentication does not automatically grant resource access.

- Namespace-scoped RBAC provides a strong least-privilege boundary without giving identities unnecessary cluster-wide permissions.

- Enabling API-server encryption affects new writes immediately but does not automatically rewrite existing stored resources.

- Encryption provider ordering matters because the first provider handles new writes while later providers allow backward-compatible reads.

- Static pod manifest backups should never be placed inside the static pod manifest directory.

- Direct etcd inspection provides stronger evidence of encryption at rest than querying Secrets through the Kubernetes API.

- The API server transparently decrypts encrypted data for authorized clients, so normal kubectl output alone cannot prove storage encryption.

- Client certificates must chain to a CA trusted by the API server's client authentication configuration.

- A newly generated private CA is not automatically trusted by the existing Kubernetes API server.

- Server certificates and client certificates require different Extended Key Usage settings.

- Certificate expiration monitoring is operationally critical because expired Kubernetes control-plane certificates can cause severe outages.

- Control-plane security changes should always include configuration backups, readiness checks, and a clear rollback path.

## Troubleshooting Log

### Kubernetes Control Plane Was Missing

The environment initially contained kubectl but no active Kubernetes control plane.

Missing components included:

- kubeadm
- kubelet
- etcdctl
- Kubernetes static pod manifests
- Kubernetes PKI
- Active kubectl context
- API server on TCP 6443

Resolution:

A kubeadm-managed Kubernetes control plane was initialized using containerd.

### Deprecated Kubernetes Package Source Avoided

Older Kubernetes installation instructions may reference legacy package repositories.

Resolution:

Kubernetes packages were installed using the current Kubernetes package repository structure.

### Static Pod Backup Location Corrected

Placing:

    kube-apiserver.yaml.backup

inside:

    /etc/kubernetes/manifests/

is unsafe because kubelet scans that directory for static pod definitions.

Resolution:

Backups were stored under:

    /etc/kubernetes/backup/

### API Server Manifest Editing Was Automated

Manual text editing of the kube-apiserver static pod manifest is error-prone and can break the control plane.

Resolution:

The YAML manifest was parsed and modified structurally using Python and PyYAML before replacing the live file.

### API Server Recovery Was Validated

After modifying the static pod manifest, the API server must restart automatically.

Resolution:

The readiness endpoint was continuously checked using:

    /readyz

Failure handling preserved the backup manifest for restoration.

### etcd Credentials Corrected

The API-server etcd client credentials were used for authenticated etcd access:

    /etc/kubernetes/pki/apiserver-etcd-client.crt
    /etc/kubernetes/pki/apiserver-etcd-client.key

rather than treating the etcd server certificate as a generic client identity.

### Existing Data Required Re-Encryption

Previously stored resources remain in their old representation after enabling encryption.

Resolution:

Secrets and ConfigMaps were rewritten through the Kubernetes API so the active encryption provider could persist them again.

### Custom CA Trust Assumption Corrected

A newly created demonstration CA is not automatically trusted by the Kubernetes API server.

Resolution:

The custom CA was used only for isolated PKI validation.

Live Kubernetes authentication used a client certificate signed through the Kubernetes CSR API.

### Custom CA Could Not Validate the Live API Server

The live API-server certificate chains to the Kubernetes cluster CA rather than the separate demonstration CA.

Resolution:

The live API connection used:

    /etc/kubernetes/pki/ca.crt

for server certificate validation.

### Client Authentication and RBAC Were Tested Separately

A client can successfully authenticate while still being forbidden from a resource.

Resolution:

Direct HTTPS requests demonstrated:

- permitted namespace request succeeds
- forbidden namespace request returns HTTP 403

This distinguishes authentication success from authorization denial.

### Certificate Monitoring Improved

Checking only certificate dates manually does not scale.

Resolution:

Both:

    kubeadm certs check-expiration

and an automated OpenSSL-based monitoring script were implemented.

## Outcome

This implementation establishes a hardened Kubernetes API-server security baseline using preventive, protective, and validation controls.

The final environment demonstrates:

- Restricted Kubernetes identities
- Least-privilege namespace access
- Client certificate authentication
- TLS-protected Kubernetes API communication
- API-server certificate validation
- Encryption of sensitive Kubernetes resources at rest
- Direct verification of encrypted etcd storage
- Certificate-chain management
- Certificate expiration monitoring
- Automated security validation

These capabilities are directly relevant to Kubernetes platform engineering, DevSecOps, cloud-native security, AIOps, and production cluster administration.
