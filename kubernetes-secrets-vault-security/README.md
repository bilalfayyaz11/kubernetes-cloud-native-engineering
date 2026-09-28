# Kubernetes Secrets Security and Vault Integration

## Overview

This implementation demonstrates a defense-in-depth approach to managing sensitive data in Kubernetes.

It combines native Kubernetes Secrets with HashiCorp Vault, Kubernetes authentication, least-privilege RBAC, encryption at rest, credential rotation, exposure scanning, and operational monitoring.

The goal is not simply to create Secrets, but to prove how sensitive data should be created, consumed, protected, rotated, and audited across a Kubernetes environment.

## Architecture

    Application Workloads
           |
           +-------------------------------+
           |                               |
           v                               v
    Kubernetes Secrets              HashiCorp Vault
           |                               |
     +-----+------+                  Kubernetes Auth
     |            |                        |
     v            v                        v
    env         volumes              Vault Agent
     |         read-only                   |
     |            |                        v
     |            |                 tmpfs shared volume
     |            |                        |
     +------------+------------------------+
                       |
                       v
                 Application Pod

    Kubernetes API
          |
          +--> Encryption at Rest
          |
          +--> RBAC
          |
          +--> Secret access boundaries

## Security Controls

| Control | Implementation |
|---|---|
| Native Secret storage | Kubernetes Secret API |
| External secrets management | HashiCorp Vault KV v2 |
| Vault workload authentication | Kubernetes ServiceAccount JWT |
| Vault authorization | Path-scoped read-only policy |
| Kubernetes authorization | Named-resource RBAC |
| Encryption at rest | K3s native secrets encryption |
| Secret environment access | secretKeyRef |
| Secret volume access | Read-only projected volume |
| Vault delivery | Vault Agent template rendering |
| Shared Vault storage | Memory-backed emptyDir |
| Credential rotation | Cryptographically generated replacement |
| Secret exposure detection | Manifest/reference scanner |
| Access visibility | Secret monitoring script |

## Environment

Validated with:

- Ubuntu 24.04 LTS
- Kubernetes via K3s
- containerd
- kubectl
- HashiCorp Vault
- Helm
- OpenSSL
- jq
- Linux shell tooling

The environment started completely fresh with kubectl installed but without a Kubernetes cluster or Vault.

K3s and Vault were installed before beginning the security implementation.

## Native Kubernetes Secrets

The implementation explored multiple Kubernetes Secret creation methods:

- imperative Secret creation
- file-based Secret creation
- manifest-based Secret creation
- TLS Secret creation

Sensitive values used during execution were generated dynamically and were not intentionally printed during verification.

### Secret Inventory

The following runtime Secret types were created:

- user credentials
- file-based credentials
- database credentials
- TLS certificate/key material
- encryption verification data

Runtime Secret values are intentionally excluded from this repository.

## Environment Variable Consumption

The environment-variable workload uses secretKeyRef references rather than embedding credentials directly in the Pod specification.

Conceptually:

    env:
      - name: DB_USERNAME
        valueFrom:
          secretKeyRef:
            name: user-credentials
            key: username

      - name: DB_PASSWORD
        valueFrom:
          secretKeyRef:
            name: user-credentials
            key: password

The validation process checked only whether these variables were present.

Their values were not intentionally displayed.

## Volume-Based Secret Consumption

A second workload mounts Kubernetes Secrets as read-only files.

The credential volume is mounted at:

    /etc/secrets

TLS material is mounted at:

    /etc/tls

The volumes use restrictive file permissions and are mounted read-only from the workload's perspective.

This pattern avoids exposing credentials through process environment inspection.

## Environment Variables vs Secret Volumes

Rotation testing demonstrated an important operational difference.

### Environment Variables

Secret-backed environment variables are resolved when the container starts.

After the Kubernetes Secret was changed, the already-running container retained its previous environment value.

The Pod required a restart to receive the rotated value.

### Secret Volumes

Secret volumes were monitored after rotation to observe Kubernetes' projected Secret refresh behavior.

This makes mounted Secret files more suitable than environment variables for applications capable of re-reading credentials dynamically.

## HashiCorp Vault

Vault was introduced as an external secrets-management system.

The implementation used:

- Vault KV v2
- Kubernetes authentication
- dedicated Vault workload identity
- path-scoped Vault policy
- Vault Agent auto-authentication
- template-based secret rendering
- memory-backed shared storage

Application credentials remained in Vault rather than being embedded directly into workload manifests.

## Vault KV Structure

Application data was logically separated into paths such as:

    secret/myapp/config
    secret/myapp/database

The implementation stored application credentials and database configuration under these paths.

Values are intentionally excluded from this repository.

## Vault Kubernetes Authentication

A dedicated Kubernetes ServiceAccount named vault-auth represents the application workload.

Vault Kubernetes authentication validates the ServiceAccount identity and maps it to a Vault role.

The role is constrained to:

    ServiceAccount: vault-auth
    Namespace: default
    Vault policy: myapp-policy

A separate reviewer identity was used for Kubernetes TokenReview operations.

## Vault Least-Privilege Policy

The application Vault policy permits read access only to the required application paths.

Policy intent:

    path "secret/data/myapp/config"
      capability: read

    path "secret/data/myapp/database"
      capability: read

The workload cannot use this policy to modify Vault secrets or access unrelated locations.

Negative tests verified:

- approved application path read: allowed
- Secret modification: denied
- unrelated Secret path access: denied

## Vault Agent Delivery

Vault Agent authenticates using the Pod's Kubernetes ServiceAccount identity.

It retrieves approved Vault secrets and renders them into:

    /vault/secrets/app-config

The shared Vault volume uses memory-backed emptyDir storage.

This means rendered secret material is kept in memory-backed ephemeral storage rather than intentionally persisted in the workload image or repository.

The application container receives the rendered configuration through a read-only volume mount.

## Vault Root Token Isolation

The Vault development root token was generated dynamically.

It was:

- not embedded in Kubernetes manifests
- not printed during the normal validation workflow
- not provided to the application container
- stored only as temporary local development state

The application uses Kubernetes authentication instead of the root token.

## Encryption at Rest

The Kubernetes cluster was configured to encrypt Secret API data at rest using the K3s secrets-encryption workflow.

Validation included:

- enabling K3s Secret encryption
- rotating encryption keys
- waiting for re-encryption completion
- checking K3s encryption status
- inspecting the generated encryption configuration with key material redacted
- writing a synthetic Secret
- verifying successful API decryption
- checking the datastore for plaintext probe content
- inspecting encrypted-data markers where available

This is different from base64 encoding.

Kubernetes Secret data returned through the API is commonly represented in base64, but base64 does not provide encryption.

## Encryption Validation Model

The test used a randomly generated synthetic probe value.

The process verified that:

1. the Secret could be created through the Kubernetes API
2. the API could return and decrypt the Secret correctly
3. the plaintext probe was not visible through the datastore inspection used in the test
4. K3s reported Secret encryption as enabled

No encryption key material is included in this repository.

## Kubernetes Secret RBAC

A dedicated ServiceAccount named secret-reader was configured with a namespace Role.

Its permitted access is limited to:

- get user-credentials
- get database-secret

It is intentionally unable to:

- read tls-secret
- list all Secrets
- create Secrets
- modify Secrets
- delete Secrets

This avoids granting broad Secret enumeration rights to application identities.

## RBAC Matrix

| Operation | Expected |
|---|---|
| Get user-credentials | Allowed |
| Get database-secret | Allowed |
| Get tls-secret | Denied |
| List Secrets | Denied |
| Create Secrets | Denied |
| Update user-credentials | Denied |
| Delete user-credentials | Denied |

## Secret Rotation

The rotation workflow generates a new password using OpenSSL and updates the Kubernetes Secret.

The generated password is not printed.

Rotation validation compares cryptographic hashes rather than exposing the credentials themselves.

The process proved:

- Secret API data changed
- running environment-variable consumers retained the previous value
- a restarted environment-variable consumer received the new value
- Secret-volume refresh behavior could be observed independently

## Exposure Scanning

The repository includes a scanner that inspects Kubernetes workload definitions for potential Secret exposure patterns.

It checks for:

- sensitive-looking inline environment variables
- secretKeyRef usage
- Secret volume references
- suspicious sensitive assignments inside container commands or arguments

The scanner reports the workload and reference location without intentionally dumping Secret contents.

## Secret Monitoring

The monitoring workflow provides operational visibility into:

- Secret inventory
- workloads consuming Secret environment references
- workloads mounting Secret volumes
- RBAC objects related to Secret access
- secret-reader authorization boundaries
- K3s Secret encryption status

This provides a lightweight way to review Secret usage across the cluster.

## Audit Policy

An audit-policy artifact is included for Metadata-level visibility into Secret API operations.

It covers:

- get
- list
- create
- update
- patch
- delete

The artifact demonstrates the intended policy.

It should not be interpreted as evidence that API-server audit logging was enabled unless the policy is explicitly configured in the Kubernetes API server startup configuration.

## Runtime Security Practices

The Secret-consuming workloads also use container hardening controls where applicable:

- non-root execution
- privilege escalation disabled
- Linux capabilities dropped
- read-only Secret mounts
- short-lived Kubernetes ServiceAccount tokens
- dedicated workload identities

Secret management is treated as one layer of workload security rather than an isolated feature.

## Key Skills Demonstrated

- Kubernetes Secrets
- Kubernetes Secret API
- secretKeyRef
- Secret volume projection
- TLS Secrets
- Kubernetes ServiceAccounts
- Kubernetes RBAC
- resourceNames-based authorization
- HashiCorp Vault
- Vault KV v2
- Vault Kubernetes authentication
- Vault Agent
- Vault templating
- least-privilege Vault policies
- TokenReview authentication
- K3s Secret encryption
- encryption-key rotation
- encryption-at-rest validation
- credential rotation
- secret lifecycle management
- secret exposure scanning
- secret access monitoring
- Kubernetes audit-policy design

## Troubleshooting and Design Decisions

### kubectl Present but No Cluster

The fresh machine contained a kubectl client but no Kubernetes API server or active context.

Resolution:

- installed K3s
- configured kubeconfig
- waited for the API server
- verified node readiness
- confirmed the Kubernetes Secret and RBAC APIs

### Vault Was Not Preinstalled

The supplied environment did not contain Vault.

Resolution:

- configured the HashiCorp package repository
- installed Vault
- created an isolated development Vault server for the security workflow

### Hard-Coded Vault Root Token

A fixed root token is inappropriate even for a portfolio security workflow.

Resolution:

- generated a random development token
- stored it with restrictive local permissions
- avoided embedding it in manifests
- used Kubernetes authentication for workloads

### Vault Networking

A Vault server bound to host loopback cannot be reached from an ordinary Kubernetes Pod by using 127.0.0.1.

Resolution:

- exposed the development listener only through the node's private interface
- configured Vault Agent to use that reachable address
- avoided binding Vault to every interface

The repository templates replace environment-specific node addresses with a placeholder.

### Secret Values in YAML

Committing actual Secret manifests containing credentials would undermine the purpose of the implementation.

Resolution:

- runtime Secret values are excluded from GitHub
- example manifests use placeholders only where useful
- generated passwords, Vault tokens, TLS private keys, and encryption keys are never committed

### Base64 Is Not Encryption

Kubernetes YAML often represents Secret data with base64 encoding.

That representation should not be considered protection of the underlying data.

Actual at-rest protection was configured through K3s Secret encryption.

### Broad Secret Listing Permission

Granting list on Secrets allows an identity to enumerate sensitive objects across its authorization scope.

Resolution:

- the secret-reader Role grants get only
- access is constrained to explicitly named Secret resources

### Vault Policy Scope

The application does not need administrative Vault privileges.

Resolution:

- only two application paths are readable
- writes are denied
- unrelated paths are denied

### Environment Variable Rotation

Updating the Kubernetes Secret does not rewrite the environment of an existing process.

Resolution:

- restart the workload when environment-based Secret values must change
- prefer file-based secret delivery when applications support dynamic reload

## Repository Contents

This directory contains safe, reusable artifacts only.

Expected artifacts include:

- README.md
- pod-env-secrets.yaml
- pod-volume-secrets.yaml
- vault-agent-config.yaml
- vault-sidecar-pod.yaml
- myapp-policy.hcl
- secret-rbac.yaml
- rotate-secret.sh
- secret-scanner.sh
- monitor-secrets.sh
- audit-policy.yaml
- findings.md

Runtime-only sensitive files are intentionally excluded.

## Security Validation Summary

| Validation | Result |
|---|---|
| Native Kubernetes Secret creation | Pass |
| Secret environment references | Pass |
| Read-only Secret volumes | Pass |
| TLS Secret handling | Pass |
| Vault KV configuration | Pass |
| Kubernetes-to-Vault authentication | Pass |
| Vault Agent rendering | Pass |
| Vault policy read boundary | Pass |
| Vault unauthorized write prevention | Pass |
| Kubernetes encryption at rest | Pass |
| API transparent decryption | Pass |
| Plaintext datastore probe | Pass |
| Named Secret RBAC | Pass |
| Secret enumeration restriction | Pass |
| Secret mutation restriction | Pass |
| Secret rotation | Pass |
| Environment restart behavior | Pass |
| Volume refresh behavior | Tested |
| Secret exposure scanning | Implemented |
| Secret monitoring | Implemented |
| Audit policy artifact | Created |

## Real-World Application

A production Kubernetes environment should not rely on a single Secret-control mechanism.

A stronger design layers:

    external secret authority
            +
    workload identity
            +
    least-privilege authorization
            +
    encrypted Kubernetes storage
            +
    safe delivery mechanisms
            +
    credential rotation
            +
    monitoring and auditing

This implementation demonstrates how those layers work together while keeping sensitive material out of source control.

## Result

The environment evolved from an empty Kubernetes client installation into a working secrets-management architecture incorporating native Kubernetes capabilities and an external secret authority.

The final design demonstrates not just how to store a Secret, but how to control who can retrieve it, how workloads receive it, how stored API data is protected, how credentials behave during rotation, and how potential exposure can be detected operationally.
