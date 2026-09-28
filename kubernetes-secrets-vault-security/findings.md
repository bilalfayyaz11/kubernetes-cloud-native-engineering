# Kubernetes Secrets Security Findings

## Native Secret Management

Secrets were created through:

- imperative creation
- file-based creation
- manifest-based creation
- Kubernetes TLS Secret creation

Secret values were intentionally excluded from validation output.

## Secret Consumption

Two consumption models were validated:

### Environment Variables

Secret values referenced through `secretKeyRef` are injected when the
container starts.

After rotating the underlying Kubernetes Secret, the already-running
container retained the previous environment value until the Pod was
restarted.

### Secret Volumes

Secrets mounted as files were configured read-only.

The mounted Secret was tested for refresh behavior after rotation,
without printing the secret value itself.

## Vault Integration

HashiCorp Vault was configured with:

- KV v2
- Kubernetes authentication
- dedicated workload ServiceAccount
- least-privilege Vault policy
- Vault Agent auto-authentication
- template-based secret rendering
- memory-backed shared secret storage

The application workload does not require the Vault root token.

## Encryption at Rest

K3s Secret encryption was enabled using its native encryption
management workflow.

Validation included:

- K3s encryption status
- generated EncryptionConfiguration inspection with key material redacted
- API round-trip decryption
- synthetic plaintext datastore search
- encrypted data marker inspection where available

## Kubernetes RBAC

The `secret-reader` ServiceAccount is limited to:

- get `user-credentials`
- get `database-secret`

It cannot:

- enumerate all Secrets
- read `tls-secret`
- create Secrets
- update Secrets
- delete Secrets

## Rotation

Secret rotation uses a cryptographically generated password and avoids
printing the resulting value.

The test demonstrated the operational difference between environment
variable consumption and volume-based Secret projection.

## Leak Scanning

A scanner checks workloads for:

- suspicious inline environment values
- SecretKeyRef usage
- Secret volume usage
- potentially sensitive command or argument content

The scanner reports references and locations rather than Secret values.

## Monitoring

The monitoring workflow reports:

- Secret inventory
- workloads referencing Secrets
- Secret volume consumers
- Secret-related RBAC
- least-privilege authorization results
- K3s encryption status

## Audit Policy

A Kubernetes audit policy artifact was created to demonstrate
Metadata-level auditing of Secret operations.

The policy is not described as active unless explicitly configured as an
API server audit policy.
