# Vault Kubernetes Secrets Management

A Kubernetes-integrated HashiCorp Vault implementation demonstrating workload authentication, least-privilege authorization, KV v2 secret management, dynamic PostgreSQL credentials, lease revocation, application integration, and audit visibility.

The implementation focuses on replacing long-lived application credentials with authenticated workload identity and short-lived secrets.

## Architecture

```text
                    Kubernetes Cluster
                           |
                           |
             +-------------+-------------+
             |                           |
             v                           v
        Vault Server                 Application
         namespace                    workload
          vault                         |
             ^                          |
             |                          |
             | Kubernetes Auth          |
             +--------------------------+
                   ServiceAccount
                   vault-auth

                           |
                           v

                 Vault Policy Engine
                           |
             +-------------+-------------+
             |                           |
             v                           v
          KV v2                     Database Engine
      Static Secrets                Dynamic Secrets
                                         |
                                         v
                                    PostgreSQL
                               short-lived identities
```

## Security Model

The application does not authenticate to Vault with a long-lived Vault token.

Instead:

```text
Kubernetes ServiceAccount
        ↓
Projected ServiceAccount JWT
        ↓
Vault Kubernetes Auth
        ↓
Vault Role
        ↓
Vault Policy
        ↓
Authorized Secret Paths
```

The Vault role is bound specifically to:

```text
ServiceAccount: vault-auth
Namespace:      vault
```

An unrelated ServiceAccount is rejected.

## Vault Policy

The application policy follows least privilege:

```hcl
path "secret/data/myapp/*" {
  capabilities = ["read"]
}

path "database/creds/my-role" {
  capabilities = ["read"]
}
```

The workload can therefore:

```text
READ   secret/data/myapp/*
READ   database/creds/my-role
```

It cannot:

```text
WRITE  application secrets
DELETE application secrets
READ   unrelated secret paths
```

## Static Secret Management

Vault KV v2 is used for application configuration such as:

```text
secret/myapp/database
secret/myapp/api
secret/myapp/config
```

Secret values are not stored in this repository.

The implementation validates:

```text
Authorized application read      PASS
Out-of-scope secret read         DENIED
Application secret modification  DENIED
```

## Kubernetes Authentication

Vault uses Kubernetes TokenReview-based identity validation.

The Vault server ServiceAccount receives the standard:

```text
system:auth-delegator
```

capability required to validate Kubernetes ServiceAccount tokens.

No manually created legacy long-lived ServiceAccount token Secret is required for the application identity.

## Dynamic PostgreSQL Credentials

Vault's database secrets engine manages PostgreSQL credentials dynamically.

The flow is:

```text
Application
    |
    | authenticated Vault request
    v
database/creds/my-role
    |
    v
Vault generates unique PostgreSQL role
    |
    +---- username
    +---- random password
    +---- lease
    +---- expiration
```

The database role is configured with limited lifetime credentials rather than static application passwords.

## Credential Lifecycle

Dynamic credentials are associated with Vault leases.

```text
Credential issued
      ↓
Database role created
      ↓
Application authenticates
      ↓
Lease remains valid
      ↓
Lease revoked / expires
      ↓
Database role removed
      ↓
Old credential rejected
```

The validation demonstrated that:

```text
Vault credential issuance             PASS
Unique PostgreSQL identity generation PASS
Real PostgreSQL authentication        PASS
Vault lease lookup                    PASS
Lease revocation                      PASS
Database identity removal             PASS
Revoked credential authentication     DENIED
```

## Application Integration

`scripts/vault-integration.sh` demonstrates application-side access without embedding Vault credentials.

The script:

```text
1. Reads its projected Kubernetes ServiceAccount token
2. Authenticates against Vault Kubernetes auth
3. Receives a scoped Vault token
4. Reads authorized static-secret metadata
5. Requests a dynamic database credential
6. Redacts sensitive values from output
```

Example conceptual flow:

```bash
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

curl \
  -X POST \
  -d "{\"jwt\":\"${JWT}\",\"role\":\"myapp-role\"}" \
  http://vault:8200/v1/auth/kubernetes/login
```

No Vault root credential is embedded in the application.

## Audit Logging

Vault audit logging records security-relevant activity including:

```text
Kubernetes authentication
Static secret reads
Dynamic database credential requests
Lease operations
```

The implementation verifies that these operations appear in the audit stream.

Raw audit logs are intentionally excluded from this repository because operational audit records can contain sensitive request metadata.

## Negative Security Tests

The implementation includes explicit authorization failures.

### Unauthorized Kubernetes identity

A workload using the namespace's default ServiceAccount attempts to authenticate against `myapp-role`.

Expected result:

```text
DENIED
```

### Out-of-scope Vault path

The approved application token attempts to read:

```text
secret/data/platform/restricted
```

Expected result:

```text
DENIED
```

### Unauthorized write

The application attempts to modify:

```text
secret/data/myapp/database
```

Expected result:

```text
DENIED
```

These tests validate the trust boundary instead of only proving successful access.

## Secret-Safe Design

Sensitive runtime material is deliberately excluded from version control.

Not committed:

```text
Vault root token
Vault unseal key
Vault initialization JSON
PostgreSQL administrator password
Dynamic database passwords
Application secret values
Kubernetes ServiceAccount tokens
Raw audit logs
Generated leases
```

Only architecture, configuration, automation, policy, sanitized evidence, and secret-free manifests are retained.

## Repository Structure

```text
vault-kubernetes-secrets-management/
├── README.md
├── .gitignore
├── config/
│   └── vault-values.yaml
├── manifests/
│   ├── auth-test-pod.yaml
│   ├── postgres.yaml
│   ├── vault-auth-serviceaccount.yaml
│   └── vault-tokenreview-binding.yaml
├── policies/
│   └── myapp-policy.hcl
├── scripts/
│   └── vault-integration.sh
└── evidence/
    ├── Kubernetes auth validation
    ├── policy validation
    ├── static secret authorization
    ├── dynamic credential validation
    ├── lease revocation results
    └── audit summaries
```

## Controls Demonstrated

```text
Kubernetes workload identity
Vault Kubernetes authentication
TokenReview integration
ServiceAccount-bound authorization
Least-privilege Vault policies
KV v2 secret management
Secret-path isolation
Dynamic PostgreSQL credentials
Short-lived database identities
Lease-based credential lifecycle
Explicit credential revocation
Application-to-Vault integration
Vault audit logging
Negative authorization testing
Secret-safe operational evidence
```

## Operational Relevance

Traditional application deployments often rely on long-lived credentials stored in environment variables, Kubernetes Secrets, CI/CD variables, or configuration files.

Vault changes that model to:

```text
Workload identity
      ↓
Authentication
      ↓
Policy evaluation
      ↓
Short-lived authorization
      ↓
Secret or credential issued
      ↓
Lease expiry / revocation
```

This reduces the lifetime and blast radius of compromised credentials while centralizing authorization and auditability.

The architecture is relevant to:

```text
Platform Engineering
DevSecOps
Kubernetes Security
Cloud-Native Security
SRE
AIOps infrastructure
Zero-Trust workload identity
```

## Production Considerations

The environment intentionally uses a compact single-server Vault deployment suitable for demonstrating the security workflow.

A production deployment would additionally introduce controls such as:

```text
Integrated Storage / Raft or supported external storage
High availability
TLS for Vault network traffic
Automatic unsealing
External KMS/HSM integration
Persistent storage
NetworkPolicies
Vault Agent or Secrets Operator integration
Backup and disaster recovery procedures
Monitoring and alerting
Root-token minimization
Regular policy and lease review
```

The key design principle remains the same:

**applications authenticate using workload identity and receive only the minimum secrets they require for the minimum amount of time.**
