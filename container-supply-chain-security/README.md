# Kubernetes Container Supply Chain Security

## Overview

This implementation demonstrates an end-to-end container supply-chain security workflow for Kubernetes.

It combines:

- Software Bill of Materials generation
- container vulnerability assessment
- immutable OCI image identity
- cryptographic image signing
- signature verification
- Kubernetes admission enforcement
- policy-as-code
- integrated security gates

The goal is to establish artifact trust before runtime rather than relying on image names, tags, or registry presence alone.

## Architecture

    Application Source
           |
           v
      Container Build
           |
           v
       OCI Registry
           |
      +----+----+
      |         |
      v         v
    Syft       Trivy
    SBOM    Vulnerability Scan
      |         |
      +----+----+
           |
           v
      Security Gate
           |
           v
    Immutable Digest
           |
           v
      Cosign Signing
           |
           v
    Signature Verification
           |
           v
     Kubernetes API
           |
           v
        Kyverno
           |
      +----+----+
      |         |
      v         v
   VERIFIED   UNTRUSTED
      |         |
      v         v
   ADMITTED    DENIED

## Security Stack

| Layer | Technology | Purpose |
|---|---|---|
| Container build | Docker | Build application artifacts |
| Registry | OCI Registry | Store registry-backed images |
| SBOM | Syft | Inventory software components |
| Vulnerability scanning | Trivy | Detect known vulnerabilities |
| Artifact identity | SHA-256 digest | Bind controls to immutable content |
| Image signing | Cosign | Cryptographically sign OCI artifacts |
| Verification | Cosign | Validate trusted signatures |
| Admission | Kyverno | Enforce image trust before execution |
| Kubernetes | KIND | Run controlled workloads |
| Automation | Shell + YAML | Implement repeatable security gates |

## Environment

Validated with:

- Ubuntu 24.04 LTS
- Docker
- KIND
- Kubernetes
- kubectl
- Syft
- Trivy
- Cosign
- Kyverno
- Helm
- jq
- OpenSSL

The environment was bootstrapped from a fresh system with no existing Kubernetes cluster, registry, signing keys, or supply-chain artifacts.

## OCI Registry

A local OCI registry was created for reproducible signing and verification.

Host endpoint:

    127.0.0.1:5001

Cluster-facing image references:

    localhost:5001

The registry was attached directly to the KIND Docker network.

This enabled:

- image pushes
- digest resolution
- Cosign signature storage
- Kubernetes image pulls
- admission-time verification

The registry intentionally uses HTTP for the isolated environment.

Production registries should use TLS and authentication.

## SBOM Generation

Syft was used to generate machine-readable and human-readable software inventories.

Formats generated:

- SPDX JSON
- CycloneDX JSON
- table output

Reference images included:

    nginx:1.28-alpine
    python:3.12-slim

Additional SBOMs were generated for:

- the signed application image
- a higher-risk comparison image

## SBOM Artifacts

    nginx-sbom.spdx.json
    nginx-sbom.cyclonedx.json
    nginx-sbom.txt

    python-sbom.spdx.json
    python-sbom.cyclonedx.json
    python-sbom.txt

    secure-app-sbom.spdx.json
    higher-risk-sbom.spdx.json

    sbom-analysis.md
    sbom-summary.json

## Why SBOMs Matter

An SBOM establishes visibility into the software contained in an artifact.

It answers:

- which packages exist
- which dependency versions are present
- which components require vulnerability tracking
- which artifact was analyzed

An SBOM does not independently determine whether the image is vulnerable or trusted.

Those properties are handled by separate security controls.

## Vulnerability Assessment

Trivy was used to evaluate container images for known vulnerabilities.

Reports were produced as structured JSON rather than relying on terminal line counts.

Severity analysis included:

- CRITICAL
- HIGH
- MEDIUM

The implementation also identifies findings with available fixed versions.

## Vulnerability Policy

The integrated security gate uses:

    Maximum CRITICAL: 0
    Maximum HIGH:     5

An artifact exceeding either threshold receives a:

    BLOCK

decision.

These values demonstrate policy enforcement mechanics and can be replaced with organization-specific thresholds.

## Higher-Risk Comparison

A separate image was created from an older Debian base to demonstrate how image selection affects vulnerability posture.

This provides a controlled comparison between:

- lighter/current application images
- a deliberately higher-risk image

The comparison reinforces that container provenance and vulnerability posture must be evaluated independently.

## Secure Application

The signed application is based on:

    nginxinc/nginx-unprivileged:1.28-alpine

The application:

- runs as a non-root user
- exposes port 8080
- drops Linux capabilities at Kubernetes runtime
- disables privilege escalation

## Immutable Artifact Identity

The secure image was pushed to the OCI registry and resolved to a SHA-256 digest.

Security decisions use the immutable form:

    localhost:5001/secure-app@sha256:<IMAGE_DIGEST>

rather than relying only on:

    localhost:5001/secure-app:v1.0

A digest permanently identifies exact image content.

A tag can move.

## Cosign Signing

A Cosign key pair was generated.

The private key was stored outside the working directory.

Only the public verification key is retained in the repository:

    cosign.pub

The signed image was cryptographically bound to its immutable OCI digest.

## Signature Verification

The signed artifact successfully passed Cosign verification.

Result:

    PASS

A second registry artifact without a valid signature was tested against the same public key.

Result:

    DENIED

This negative test demonstrates that verification is actually distinguishing trusted and untrusted artifacts.

## Private Key Protection

The private signing key:

    cosign.key

is intentionally excluded from repository artifacts.

The packaging workflow also checks staged content for private-key material before commit.

## Kubernetes Admission Enforcement

Kyverno was configured to perform real Cosign signature verification.

Policy scope:

    namespace: supply-chain-demo

Registry scope:

    localhost:5001/*

Trust anchor:

    cosign.pub

## Admission Model

Kubernetes does not infer trust from:

- image names
- tags
- repository naming
- strings such as "secure"

The OCI artifact must carry a valid signature from the configured trusted key.

## Signed Artifact Admission

The signed digest was submitted through Kubernetes admission.

Result:

    ALLOWED

The workload successfully ran in the cluster.

## Unsigned Artifact Admission

A second unsigned OCI artifact was submitted using the same admission path.

Result:

    DENIED

The unsigned workload was prevented from producing an admitted Pod.

## Why Real Verification Matters

A naming convention is not proof of provenance.

Checking whether an image name contains:

    secure

does not validate a signature.

This implementation instead performs cryptographic verification against the actual OCI artifact.

## Integrated Security Pipeline

The reusable pipeline:

    security-pipeline.sh

evaluates multiple security properties independently.

### Gate 1 — Immutable Reference

The artifact reference must contain:

    @sha256:

Tag-only references are blocked.

### Gate 2 — SBOM Generation

Syft must successfully produce an SPDX SBOM.

### Gate 3 — Vulnerability Scan

Trivy must successfully generate structured vulnerability data.

### Gate 4 — Vulnerability Threshold

The artifact must satisfy:

    CRITICAL <= 0
    HIGH     <= 5

### Gate 5 — Signature Verification

Cosign must successfully validate the image against:

    cosign.pub

## Decision Logic

    immutable digest
          AND
    SBOM generated
          AND
    vulnerability scan successful
          AND
    vulnerability threshold satisfied
          AND
    valid Cosign signature
          =
        ALLOW

Any failed control results in:

        BLOCK

## Final Signed-Image Pipeline Result

The signed application passed:

- immutable-reference verification
- SBOM generation
- vulnerability scanning
- Cosign signature verification

Trivy identified:

    CRITICAL: 3
    HIGH:     60

Configured policy:

    Maximum CRITICAL: 0
    Maximum HIGH:     5

Final integrated decision:

    BLOCK

This is the expected security behavior.

The image is authentic and correctly signed, but it does not satisfy the vulnerability policy.

## Important Security Principle

A signed image is not automatically a safe image.

Cosign answers:

    Was this artifact signed by the trusted signing identity?

Trivy answers:

    What known vulnerabilities exist in the artifact?

These are separate questions.

A trusted artifact may still contain vulnerabilities.

A low-vulnerability artifact may still come from an untrusted source.

Both controls must be evaluated.

## Negative Pipeline Tests

### Unsigned Immutable Artifact

Result:

    BLOCK

Reason:

    valid Cosign signature not present

### Mutable Tag Reference

Result:

    BLOCK

Reason:

    immutable digest requirement not satisfied

### Signed Artifact Exceeding Vulnerability Threshold

Result:

    BLOCK

Reason:

    vulnerability policy violation

These negative controls demonstrate that one successful control cannot bypass another failed control.

## Syft Local Registry Behavior

During integrated pipeline testing, Syft registry-source analysis against the isolated HTTP registry stalled.

Direct registry scanning was therefore not used as the final SBOM analysis path.

Instead, the workflow separates:

- deployment identity
- analysis source

Deployment identity remains the immutable registry digest:

    localhost:5001/secure-app@sha256:<IMAGE_DIGEST>

SBOM analysis uses the identical locally available Docker image:

    docker:secure-app:v1.0

This preserves artifact identity for signing and admission while avoiding unreliable registry-source scanning in the local development environment.

## Policy as Code

The logical supply-chain requirements are also represented in:

    supply-chain-policy.yaml

Policy intent includes:

    SBOM required: true

    Immutable digest required: true

    Vulnerability scan required: true

    Maximum CRITICAL: 0

    Maximum HIGH: 5

    Signature required: true

    Verification method: Cosign

    Allowed registry:
      localhost:5001

    Signed artifact admission:
      required

## Runtime Security

The signed workload also uses Kubernetes runtime controls:

    allowPrivilegeEscalation: false
    runAsNonRoot: true
    capabilities:
      drop:
        - ALL

Supply-chain security and runtime security address different attack surfaces.

## Evidence

### SBOM

    nginx-sbom.spdx.json
    nginx-sbom.cyclonedx.json
    python-sbom.spdx.json
    python-sbom.cyclonedx.json
    secure-app-sbom.spdx.json
    higher-risk-sbom.spdx.json
    sbom-analysis.md
    sbom-summary.json

### Vulnerability Assessment

    nginx-vuln-report.json
    python-vuln-report.json
    higher-risk-vuln-report.json
    secure-app-vuln-report.json
    vulnerability-analysis.md
    vulnerability-summary.json

### Signing

    cosign.pub
    signing-analysis.md
    signing-metadata.json
    secure-app-signature-verification.json
    verify-signature.sh

### Admission Enforcement

    verify-signed-images.yaml
    signed-pod.yaml
    unsigned-pod.yaml
    signed-deployment.yaml
    unsigned-deployment.yaml
    admission-analysis.md

### Pipeline and Policy

    security-pipeline.sh
    supply-chain-policy.yaml
    supply-chain-architecture.md
    findings.md
    pipeline-findings.md
    security-summary.json

## Skills Demonstrated

- Software Bill of Materials
- SPDX
- CycloneDX
- Syft
- container vulnerability scanning
- Trivy
- structured vulnerability analysis
- remediation visibility
- vulnerability thresholds
- OCI registries
- immutable image digests
- container image signing
- Cosign
- public-key verification
- signing-key isolation
- negative signature testing
- Kubernetes admission control
- Kyverno
- cryptographic image verification
- policy-as-code
- Docker
- KIND
- Kubernetes
- container runtime security
- supply-chain policy gates
- DevSecOps automation

## Control Responsibilities

| Control | Question |
|---|---|
| SBOM | What software is inside the image? |
| Trivy | What known vulnerabilities affect it? |
| Digest | Which exact artifact is being evaluated? |
| Cosign | Is the artifact signed by a trusted signer? |
| Kyverno | May Kubernetes admit the artifact? |
| Integrated pipeline | Does the artifact satisfy all required controls? |

## Final Results

| Control | Result |
|---|---|
| SPDX SBOM generation | Pass |
| CycloneDX SBOM generation | Pass |
| Dependency analysis | Pass |
| Trivy scanning | Pass |
| Structured severity analysis | Pass |
| OCI registry | Pass |
| Immutable digest identification | Pass |
| Cosign signing | Pass |
| Cosign verification | Pass |
| Unsigned signature test | Denied |
| Private key isolation | Pass |
| Kyverno admission controller | Active |
| Signed artifact admission | Allowed |
| Unsigned artifact admission | Denied |
| Mutable tag pipeline test | Blocked |
| Vulnerability policy | Enforced |
| Signed-image integrated decision | Blocked by vulnerability threshold |
| Policy as code | Implemented |
| Integrated security pipeline | Implemented |

## Result

The environment demonstrates a container trust chain from software inventory through Kubernetes admission.

The final workflow does not treat signing, vulnerability scanning, or registry presence as interchangeable security signals.

Instead, it independently evaluates:

- software composition
- known vulnerabilities
- immutable artifact identity
- cryptographic provenance
- Kubernetes admission trust

The signed image was correctly recognized as authentic while still being blocked by the integrated security policy because its vulnerability posture exceeded the configured thresholds.

That separation of controls is the core supply-chain security outcome demonstrated here.
