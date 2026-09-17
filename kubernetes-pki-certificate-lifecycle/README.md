# Kubernetes PKI Certificate Lifecycle

A Kubernetes-focused Public Key Infrastructure implementation demonstrating hierarchical certificate authority design, component identity issuance, certificate-chain validation, kubeconfig credential construction, expiry monitoring, and safe certificate rotation.

The implementation builds the trust model independently of a running Kubernetes control plane so the certificate hierarchy and lifecycle mechanics can be inspected and validated directly.

## Architecture

```text
                     Kubernetes Root CA
                       RSA-4096
                       CA:TRUE
                           |
                           |
                           v
                Kubernetes Intermediate CA
                       RSA-4096
                 CA:TRUE, pathlen:0
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
   kube-apiserver         etcd           kubelet
      RSA-2048          RSA-2048         RSA-2048
   server/client      server/client       client
       auth               auth             auth

                           |
                           v
                         admin
                       RSA-2048
                     clientAuth
```

## Trust Model

The hierarchy separates the long-lived trust anchor from day-to-day certificate issuance.

The root CA signs only the intermediate CA.

The intermediate CA has:

```text
CA:TRUE
pathlen:0
keyCertSign
cRLSign
```

`pathlen:0` prevents the intermediate from establishing another subordinate CA beneath itself when the chain is validated with the constraint enforced.

Leaf certificates are issued for distinct Kubernetes identities with certificate extensions appropriate to their role.

## Issued Identities

| Identity | Authentication Role | Key Size | Validity |
|---|---|---:|---:|
| Kubernetes Root CA | Root trust anchor | RSA-4096 | 3650 days |
| Kubernetes Intermediate CA | Certificate issuer | RSA-4096 | 1825 days |
| kube-apiserver | Server + client TLS | RSA-2048 | 365 days |
| etcd | Server + client TLS | RSA-2048 | 365 days |
| system:node:worker-1 | Kubelet client identity | RSA-2048 | 365 days |
| admin | Administrative client identity | RSA-2048 | 365 days |

## API Server Identity

The API server certificate contains the Kubernetes service identities required for TLS hostname verification.

```text
DNS:kubernetes
DNS:kubernetes.default
DNS:kubernetes.default.svc
DNS:kubernetes.default.svc.cluster.local
DNS:localhost

IP:127.0.0.1
IP:10.96.0.1
```

Extended key usage:

```text
TLS Web Server Authentication
TLS Web Client Authentication
```

## etcd Identity

The etcd certificate is constrained to its expected service identities:

```text
DNS:localhost
DNS:etcd.kube-system.svc.cluster.local
IP:127.0.0.1
```

It supports both server and client authentication.

## Kubelet Identity

The kubelet certificate represents:

```text
CN = system:node:worker-1
O  = system:nodes
```

Its certificate is restricted to client authentication.

## Administrator Identity

The administrative identity uses:

```text
CN = admin
O  = system:masters
```

and is issued strictly for client authentication.

## Certificate Chain Validation

The CA chain is ordered:

```text
Intermediate CA
Root CA
```

Leaf credentials can be validated with:

```bash
openssl verify \
  -CAfile certificates/ca-chain.pem \
  certificates/api-server.pem \
  certificates/etcd.pem \
  certificates/kubelet.pem \
  certificates/admin.pem
```

Expected result:

```text
certificates/api-server.pem: OK
certificates/etcd.pem: OK
certificates/kubelet.pem: OK
certificates/admin.pem: OK
```

## Certificate Expiry Monitoring

`scripts/pki-monitor.sh` provides deterministic lifecycle health checks.

Usage:

```bash
./scripts/pki-monitor.sh
./scripts/pki-monitor.sh --warn-days 30
```

Exit-code contract:

| Code | Meaning |
|---:|---|
| `0` | Certificates are healthy outside the warning window |
| `1` | At least one certificate is expired or invalid |
| `2` | At least one certificate is inside the warning window |

Example:

```bash
./scripts/pki-monitor.sh --warn-days 400
```

The 365-day component certificates enter warning state while longer-lived CA certificates remain healthy.

A narrow threshold:

```bash
./scripts/pki-monitor.sh --warn-days 10
```

returns healthy status when none of the credentials are approaching expiration.

## Safe Certificate Rotation

`scripts/pki-rotate.sh` implements controlled credential replacement for:

```text
api-server
etcd
kubelet
admin
```

Usage:

```bash
./scripts/pki-rotate.sh api-server
```

The rotation sequence is:

```text
Generate replacement key
        |
        v
Generate replacement CSR
        |
        v
Issue replacement certificate
        |
        v
Verify replacement against CA chain
        |
        v
Verify certificate/key match
        |
        v
Create timestamped archive
        |
        v
Archive current credential
        |
        v
Atomically replace live files
        |
        v
Validate new live certificate
        |
        v
Validate recent notBefore timestamp
        |
        +------ failure ------> rollback archived credential
```

The live certificate is never deliberately removed before a verified replacement exists.

## Rotation History

Before replacement, the previous credential pair is retained under a timestamped structure:

```text
pki/archive/
└── api-server/
    └── YYYYMMDDTHHMMSSZ/
        ├── api-server.pem
        └── api-server-key.pem
```

Private archive contents are intentionally excluded from this repository.

## Negative Trust Validation

The trust model was also tested against invalid paths.

### Self-Signed Identity

An independently self-signed client certificate was checked against the Kubernetes CA chain and rejected.

### Unrelated Certificate Authority

A valid API server certificate was tested against an unrelated root CA and rejected.

### CA Path-Length Enforcement

A subordinate CA was signed using the intermediate credential as a negative test.

Strict OpenSSL validation rejects the resulting chain because the intermediate contains:

```text
pathlen:0
```

This demonstrates enforcement of the intended CA hierarchy rather than only successful certificate issuance.

## Credential Protection

Generated private keys use:

```text
0400
```

PKI directories are restricted to the owning user.

Kubeconfigs containing embedded private key material are not included in version control.

The repository contains only:

```text
public certificates
OpenSSL configuration
lifecycle automation
sanitized validation evidence
```

## Embedded Kubeconfig Design

The generated administrator and kubelet kubeconfigs use inline base64-encoded credentials rather than filesystem references:

```yaml
certificate-authority-data: <embedded CA chain>
client-certificate-data: <embedded client certificate>
client-key-data: <embedded private key>
server: https://127.0.0.1:6443
```

Those generated kubeconfigs are intentionally excluded because they contain private cryptographic material.

## Repository Structure

```text
kubernetes-pki-certificate-lifecycle/
├── README.md
├── .gitignore
├── certificates/
│   ├── root-ca.pem
│   ├── intermediate-ca.pem
│   ├── ca-chain.pem
│   ├── api-server.pem
│   ├── etcd.pem
│   ├── kubelet.pem
│   └── admin.pem
├── config/
│   ├── root-ca.cnf
│   ├── intermediate-ca.cnf
│   ├── intermediate-ca-ext.cnf
│   ├── api-server.cnf
│   ├── api-server-ext.cnf
│   ├── etcd.cnf
│   ├── etcd-ext.cnf
│   ├── kubelet.cnf
│   ├── kubelet-ext.cnf
│   ├── admin.cnf
│   └── admin-ext.cnf
├── scripts/
│   ├── pki-monitor.sh
│   └── pki-rotate.sh
└── evidence/
    ├── CA hierarchy validation
    ├── certificate extension validation
    ├── chain verification
    ├── expiry-monitor results
    ├── rotation validation
    └── negative trust tests
```

## Security Properties Demonstrated

```text
Hierarchical CA design
X.509 certificate-chain validation
Basic Constraints enforcement
CA path-length restriction
Key Usage enforcement
Extended Key Usage enforcement
Subject Alternative Name management
Kubernetes component identity modeling
Mutual-TLS credential preparation
Secure private-key permissions
Embedded kubeconfig credentials
Certificate expiry monitoring
Deterministic lifecycle exit codes
Certificate/key consistency validation
Pre-replacement chain verification
Credential archival
Atomic certificate replacement
Rollback protection
Negative trust-path testing
```

## Operational Relevance

Certificate failures in Kubernetes can affect control-plane availability, node authentication, administrative access, and communication with etcd.

The implementation therefore treats PKI as an operational lifecycle rather than a one-time certificate-generation process:

```text
Issue
  ↓
Validate
  ↓
Deploy
  ↓
Monitor
  ↓
Rotate
  ↓
Archive
  ↓
Validate again
```

That model is applicable to Kubernetes platform engineering, cloud-native security, DevSecOps, SRE, and infrastructure automation.
