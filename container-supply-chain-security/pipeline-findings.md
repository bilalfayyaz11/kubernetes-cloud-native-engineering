# Integrated Supply Chain Pipeline Findings

## Signed Artifact

Artifact:

`localhost:5001/secure-app@sha256:<IMAGE_DIGEST>`

Signature verification:

**PASS**

Observed Trivy findings:

- CRITICAL: 3
- HIGH: 60

Configured threshold:

- Maximum CRITICAL: 0
- Maximum HIGH: 5

Final policy result:

**BLOCK**

This is an expected security result.

A valid cryptographic signature proves that the artifact was signed by
the trusted key and that the signed content has not changed.

It does not prove that the image is free from known vulnerabilities.

## Unsigned Artifact

Artifact:

`localhost:5001/unsigned-nginx@sha256:<IMAGE_DIGEST>`

Expected result:

**BLOCK**

The image fails Cosign verification because it does not carry a valid
signature from the trusted signing key.

## Mutable Reference

A tag-only reference is also rejected by the integrated pipeline.

This prevents a security decision from being attached only to a mutable
tag whose underlying image content could later change.

## SBOM Analysis Path

The local development registry caused Syft registry-source scans to stall.

The pipeline therefore separates:

- deployment identity — immutable OCI registry digest
- analysis source — the identical locally available Docker image

The image digest remains the identity used for signing and Kubernetes
admission.

SBOM generation is performed against the local copy of the same built
artifact.

## Security Conclusion

The final workflow demonstrates independent supply-chain controls:

1. immutable artifact identity
2. SBOM generation
3. vulnerability assessment
4. explicit severity thresholds
5. cryptographic signature verification
6. Kubernetes admission enforcement

Passing one control does not bypass failure in another.
