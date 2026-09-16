# Signed Container Supply Chain Enforcement

## What This Does

This implementation establishes an end-to-end container supply-chain security workflow that prevents untrusted artifacts from reaching Kubernetes workloads.

Container images are scanned with Trivy and must contain zero HIGH or CRITICAL vulnerabilities before progressing to cryptographic signing with Cosign. Approved artifacts are signed using an immutable OCI image digest and receive a provenance attestation describing the build and vulnerability assessment.

At deployment time, a TLS-secured Kubernetes ValidatingAdmissionWebhook independently verifies each container image using the Cosign public key. Images without a valid signature, malformed references, verification failures, or internal webhook errors are rejected before the workload is persisted by the Kubernetes API server.

## Architecture

```text
                    CONTAINER SUPPLY CHAIN

┌──────────────────────────────────────────────────────────────┐
│                      BUILD & SCAN LAYER                      │
│                                                              │
│  Python HTTP Service                                         │
│         │                                                    │
│         ▼                                                    │
│  Docker Build                                                │
│         │                                                    │
│         ▼                                                    │
│  Trivy Vulnerability Gate                                    │
│  HIGH = 0 / CRITICAL = 0                                    │
│         │                                                    │
│    ┌────┴────┐                                               │
│    │         │                                               │
│   PASS      FAIL                                             │
│    │         │                                               │
│    ▼         └──────────────► Reject Artifact                │
└────┬─────────────────────────────────────────────────────────┘
     │
     ▼
┌──────────────────────────────────────────────────────────────┐
│                    ARTIFACT TRUST LAYER                      │
│                                                              │
│  Local OCI Registry                                          │
│         │                                                    │
│         ▼                                                    │
│  Immutable Image Digest                                      │
│         │                                                    │
│    ┌────┴───────────┐                                        │
│    │                │                                        │
│    ▼                ▼                                        │
│ Cosign           Provenance                                  │
│ Signature        Attestation                                 │
│    │                │                                        │
│    └───────┬────────┘                                        │
│            ▼                                                 │
│    Public-Key Verification                                   │
└────────────┬─────────────────────────────────────────────────┘
             │
             ▼
┌──────────────────────────────────────────────────────────────┐
│                 KUBERNETES ENFORCEMENT                      │
│                                                              │
│  Pod CREATE Request                                          │
│         │                                                    │
│         ▼                                                    │
│  Kubernetes API Server                                       │
│         │                                                    │
│         ▼                                                    │
│  ValidatingAdmissionWebhook                                  │
│         │                                                    │
│         ▼                                                    │
│  Cosign Signature Verification                               │
│         │                                                    │
│    ┌────┴─────┐                                              │
│    │          │                                              │
│  VALID      INVALID                                          │
│    │          │                                              │
│    ▼          ▼                                              │
│  Admit       Deny                                            │
│  Pod         Request                                         │
│                                                              │
│              failurePolicy: Fail                             │
└──────────────────────────────────────────────────────────────┘
```

## Security Controls

The implementation enforces security at three independent boundaries:

1. **Build-time vulnerability control**  
   Trivy evaluates the container image and blocks progression when HIGH or CRITICAL vulnerabilities are detected.

2. **Artifact identity and provenance**  
   Cosign cryptographically signs the immutable OCI digest and attaches a custom provenance attestation.

3. **Runtime admission enforcement**  
   Kubernetes verifies the artifact signature before accepting a Pod into the cluster.

This layered approach prevents a vulnerability scanner, signing system, or Kubernetes deployment path from becoming a single point of trust.

## Prerequisites

The following tooling is required:

- Ubuntu Linux
- Docker Engine
- kubectl
- kind
- Trivy
- Cosign
- Python 3
- PyYAML
- OpenSSL
- jq
- curl
- Git
- Internet connectivity for container images and vulnerability databases

Verify the environment:

```bash
docker --version
kubectl version --client
kind version
trivy --version
cosign version
python3 --version
openssl version
jq --version
```

## Environment Setup

Create the Kubernetes environment:

```bash
kind create cluster \
  --name supply-chain-security \
  --wait 120s

kubectl get nodes
kubectl get pods -A
```

Create the local OCI registry:

```bash
docker run -d \
  --restart unless-stopped \
  --name supply-chain-registry \
  -p 5000:5000 \
  registry:2
```

Verify registry availability:

```bash
curl http://127.0.0.1:5000/v2/
```

## Application Image

The containerized application is a lightweight Python HTTP service exposing:

```text
GET /health
```

The container runs as a non-root user and exposes port `8080`.

Build the image:

```bash
docker build \
  -t supply-chain-api:1.0 \
  .
```

Run it locally:

```bash
docker run -d \
  --name supply-chain-api-test \
  -p 18080:8080 \
  supply-chain-api:1.0
```

Validate the health endpoint:

```bash
curl http://127.0.0.1:18080/health
```

Expected response:

```json
{"status": "ok"}
```

Clean up:

```bash
docker rm -f supply-chain-api-test
```

## Vulnerability Gate

The executable security gate is located at:

```text
scripts/scan-gate.sh
```

Run it against an image:

```bash
./scripts/scan-gate.sh supply-chain-api:1.0
```

The gate:

- accepts exactly one image reference
- invokes Trivy
- scans HIGH and CRITICAL severities
- produces a structured JSON report
- stores evidence under `reports/`
- counts HIGH and CRITICAL findings
- exits successfully only when both counts are zero
- exits non-zero when vulnerabilities or scanner errors occur

Security condition:

```text
HIGH + CRITICAL = 0  -> PASS
HIGH + CRITICAL > 0  -> FAIL
```

This makes the scan usable as a deterministic CI/CD security control instead of an informational report.

## OCI Registry

Tag the approved image for the local registry:

```bash
docker tag \
  supply-chain-api:1.0 \
  localhost:5000/supply-chain-api:1.0
```

Push it:

```bash
docker push \
  localhost:5000/supply-chain-api:1.0
```

The image is subsequently identified by its immutable SHA-256 digest rather than by its mutable tag.

Example:

```text
localhost:5000/supply-chain-api@sha256:<digest>
```

## Cryptographic Signing

Create a protected key directory:

```bash
mkdir -p keys
chmod 700 keys
```

Set the key encryption password:

```bash
export COSIGN_PASSWORD='<secure-password>'
```

Generate the key pair:

```bash
cosign generate-key-pair \
  --output-key-prefix keys/cosign
```

Generated files:

```text
keys/cosign.key
keys/cosign.pub
```

The private key must never be committed to source control.

Sign the immutable image:

```bash
cosign sign \
  --key keys/cosign.key \
  --tlog-upload=false \
  --allow-http-registry \
  localhost:5000/supply-chain-api@sha256:<digest>
```

Verify the signature:

```bash
cosign verify \
  --key keys/cosign.pub \
  --insecure-ignore-tlog=true \
  --allow-http-registry \
  localhost:5000/supply-chain-api@sha256:<digest>
```

Successful verification proves that the artifact corresponding to the immutable digest was signed by the holder of the matching private key.

## Provenance Attestation

The custom provenance predicate records:

- image repository
- immutable image digest
- vulnerability scan result
- HIGH vulnerability count
- CRITICAL vulnerability count
- signing timestamp
- build identifier
- security thresholds

Example structure:

```json
{
  "image": "localhost:5000/supply-chain-api",
  "digest": "sha256:<digest>",
  "scan": {
    "result": "PASS",
    "high": 0,
    "critical": 0
  },
  "signingTimestamp": "<timestamp>",
  "buildId": "<build-id>",
  "securityPolicy": {
    "maxHigh": 0,
    "maxCritical": 0
  }
}
```

Attach the attestation:

```bash
cosign attest \
  --key keys/cosign.key \
  --type custom \
  --predicate attestations/provenance.json \
  --tlog-upload=false \
  --allow-http-registry \
  localhost:5000/supply-chain-api@sha256:<digest>
```

Verify it:

```bash
cosign verify-attestation \
  --key keys/cosign.pub \
  --type custom \
  --insecure-ignore-tlog=true \
  --allow-http-registry \
  localhost:5000/supply-chain-api@sha256:<digest>
```

The verification process requires only the public key.

## Kubernetes Admission Enforcement

A custom Python HTTPS webhook implements Kubernetes `AdmissionReview` processing.

The webhook:

- intercepts Pod CREATE requests
- extracts init-container and application-container image references
- verifies every image with Cosign
- uses the public key mounted from a Kubernetes Secret
- communicates with the API server using TLS
- runs as a non-root container
- drops Linux capabilities
- stores no session state
- denies any failed signature verification
- denies internal verification errors
- operates with `failurePolicy: Fail`
- uses a 10-second admission timeout

## Public-Key Distribution

The Cosign public key is stored as a Kubernetes Secret:

```bash
kubectl -n supply-chain-security \
  create secret generic cosign-public-key \
  --from-file=cosign.pub=keys/cosign.pub
```

The key is mounted read-only into the admission webhook container.

The private signing key is never deployed into Kubernetes.

## TLS

The admission webhook communicates with the API server over HTTPS.

The certificate includes the Kubernetes service DNS identities:

```text
signature-policy.supply-chain-security.svc
signature-policy.supply-chain-security.svc.cluster.local
```

The certificate authority is embedded into the `ValidatingWebhookConfiguration` as `caBundle`.

## Deployment

Deploy the webhook workload and Service:

```bash
kubectl apply \
  -f k8s/webhook-deployment.yaml
```

Deploy the admission configuration:

```bash
kubectl apply \
  -f k8s/validating-webhook.yaml
```

Verify the webhook workload:

```bash
kubectl get pods \
  -n supply-chain-security
```

Verify admission configuration:

```bash
kubectl get validatingwebhookconfiguration \
  signature-policy
```

## Namespace Scope

Signature enforcement targets Pod creation in the `default` namespace.

The webhook itself runs in:

```text
supply-chain-security
```

Separating the webhook workload from the protected namespace prevents the policy from blocking its own recovery or deployment.

## Signed Workload Validation

The trusted workload references the image using its immutable digest:

```text
localhost:5000/supply-chain-api@sha256:<digest>
```

and explicitly uses:

```yaml
imagePullPolicy: Never
```

Apply it:

```bash
kubectl apply \
  -f k8s/signed-pod.yaml
```

Verify:

```bash
kubectl get pod \
  signed-api \
  -n default
```

Expected result:

```text
signed-api   Running
```

This demonstrates successful admission after cryptographic verification.

## Unsigned Workload Validation

An unsigned `nginx:latest` workload is used as the negative security test.

Attempt creation:

```bash
kubectl apply \
  -f k8s/unsigned-pod.yaml
```

Expected behavior:

```text
Pod creation denied by the signature admission policy
```

Verify that the denied workload was never persisted:

```bash
kubectl get pod \
  unsigned-nginx \
  -n default
```

Expected result:

```text
NotFound
```

## Enforcement Decision Flow

```text
Pod CREATE
    │
    ▼
API Server
    │
    ▼
ValidatingAdmissionWebhook
    │
    ▼
Extract Image References
    │
    ▼
Cosign Verify
    │
    ├──── Signature Valid ────► Continue
    │
    └──── Invalid / Error ────► DENY
                                  │
                                  ▼
                         Workload Not Persisted
```

## Project Structure

```text
.
├── Dockerfile
├── Dockerfile.webhook
├── README.md
├── app
│   ├── server.py
│   └── webhook.py
├── attestations
│   └── provenance.json
├── keys
│   └── cosign.pub
├── k8s
│   ├── signed-pod.yaml
│   ├── unsigned-pod.yaml
│   ├── validating-webhook.yaml
│   └── webhook-deployment.yaml
├── reports
│   └── *.json
└── scripts
    └── scan-gate.sh
```

Sensitive files are intentionally excluded.

## Tools Used

- Docker
- Kubernetes
- kind
- Trivy
- Cosign
- Sigstore
- OCI Registry
- Python
- Kubernetes AdmissionReview API
- ValidatingAdmissionWebhook
- OpenSSL
- jq
- Bash
- Git

## Key Skills Demonstrated

- Container vulnerability assessment
- Automated vulnerability threshold enforcement
- Secure container image construction
- Non-root container execution
- OCI image registry workflows
- Immutable digest-based artifact identity
- Public-key cryptography
- Container image signing
- Software provenance attestations
- Signature verification
- Kubernetes admission control
- AdmissionReview processing
- Fail-closed security architecture
- TLS-secured Kubernetes webhooks
- Kubernetes Secret-based public-key distribution
- Runtime artifact integrity enforcement
- Container supply-chain security
- Security automation
- Failure diagnostics across OCI, Docker, Cosign, and Kubernetes

## Real-World Use Case

This architecture can be placed between CI artifact creation and a production Kubernetes cluster. Images that fail vulnerability policy never become trusted artifacts. Approved images receive a cryptographic identity and provenance record, while Kubernetes independently validates that identity before admitting workloads.

The control prevents direct deployment of unsigned images even when a user has permission to submit Kubernetes manifests. It also protects against mutable-tag substitution because deployment decisions are tied to immutable OCI digests.

In larger environments, the same architecture can be integrated with CI systems, enterprise registries, policy engines, workload identity, managed key services, Sigstore infrastructure, Kyverno, or OPA Gatekeeper.

## Security Properties

### Vulnerability enforcement

Only images satisfying the defined severity threshold progress to signing.

### Artifact integrity

The signature is bound to the immutable OCI image digest.

### Provenance

The attestation associates the artifact with its scan result, build identity, timestamp, and security policy.

### Separation of keys

Only the public key reaches Kubernetes. The private signing key remains outside the runtime environment.

### Fail-closed admission

Verification failures and internal webhook errors deny the workload instead of silently allowing execution.

### Immutable deployment

Trusted workloads reference digests rather than mutable tags.

## Lessons Learned

- Vulnerability reports become substantially more useful when converted into deterministic deployment gates.
- Image tags are mutable and should not be treated as cryptographic artifact identities.
- Signing should operate against immutable OCI digests.
- Cosign signatures and attestations rely on registry-backed OCI artifacts rather than only a local Docker image cache.
- Admission controls provide an independent trust boundary even when earlier pipeline controls are bypassed.
- Public signing keys can safely be distributed to verification components while private keys remain isolated.
- Webhooks protecting workloads should avoid protecting their own namespace unless recovery behavior has been deliberately designed.
- Fail-open behavior can transform infrastructure failures into security bypasses; fail-closed behavior prevents that class of bypass.

## Troubleshooting Log

### Docker Access

Docker was installed and its service was active, but the non-root user initially lacked access to the Docker socket.

Access was configured before provisioning the containerized Kubernetes environment.

### Outdated Tool Versions

Older pinned versions of Kubernetes tooling and Cosign were avoided where the existing environment already provided newer compatible components.

This prevented unnecessary downgrades and version conflicts.

### OCI Registry Requirement

Signing could not rely solely on the Docker daemon's local image cache.

A local OCI registry was introduced so the image manifest, Cosign signature, and provenance attestation could exist as registry-backed artifacts.

### Registry Networking

The host referenced the registry as:

```text
localhost:5000
```

Inside the Kubernetes admission webhook, `localhost` referred to the webhook container itself.

The registry was attached to the kind Docker network, and the webhook translated the host-facing image repository to the registry's internal network endpoint during verification.

### Malformed Digest Reference

Initial digest construction produced:

```text
localhost:5000/supply-chain-api@supply-chain-api@sha256:...
```

The repository component was duplicated.

Digest resolution was corrected to produce the canonical immutable reference:

```text
localhost:5000/supply-chain-api@sha256:<digest>
```

### Admission Webhook HTTP 404

The Kubernetes API server called:

```text
/validate?timeout=10s
```

The initial Python implementation compared the entire HTTP request target directly against:

```text
/validate
```

Because the query string was included, the handler returned HTTP 404.

The webhook was corrected to parse the request URI and compare only its path component before processing the AdmissionReview.

### Fail-Closed Validation

The webhook uses:

```text
failurePolicy: Fail
```

During webhook implementation issues, Kubernetes denied workload creation rather than bypassing verification.

That failure behavior confirmed the admission boundary was operating fail-closed.

## Final Validation

The completed security chain demonstrated:

```text
Container Build
      │
      ▼
Trivy Security Gate
      │
      ▼
Immutable OCI Digest
      │
      ▼
Cosign Signature
      │
      ▼
Provenance Attestation
      │
      ▼
Kubernetes Admission Verification
      │
      ├──── Signed ────► ADMITTED
      │
      └──── Unsigned ──► DENIED
```

Final validated outcomes:

- the application image ran as a non-root user
- the vulnerability security gate generated structured audit evidence
- the approved artifact satisfied the zero HIGH/CRITICAL threshold
- the image was pushed into an OCI registry
- the immutable image digest was cryptographically signed
- the Cosign signature was successfully verified
- a custom provenance attestation was attached
- the provenance attestation was successfully verified
- the Cosign public key was mounted from a Kubernetes Secret
- the admission webhook communicated using TLS
- the admission webhook operated fail-closed
- the digest-pinned signed workload was admitted
- the signed workload reached Running state
- the unsigned workload was rejected by the Kubernetes API server
- the rejected workload was never persisted

