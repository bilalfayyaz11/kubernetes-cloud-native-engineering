# Container Image Signing Analysis

## Image

Registry tag:

`localhost:5001/secure-app:v1.0`

Immutable signed reference:

`localhost:5001/secure-app@sha256:<IMAGE_DIGEST>`

## Signing Model

The container image was pushed to an OCI registry before signing.

Cosign signed the immutable image digest rather than relying only on the
mutable tag.

## Key Management

A Cosign key pair was generated for the workflow.

The private signing key is stored outside the working directory and must
not be committed to source control.

Only the public verification key is retained with the reusable security
artifacts.

## Verification

Cryptographic verification succeeded for the signed secure application.

A separate unsigned image was pushed to the same registry and tested with
the same public key.

The unsigned image failed verification as expected.

## Vulnerability Context

Critical findings: 3

High findings: 60

Image signing proves artifact authenticity and integrity. It does not prove
that the artifact contains no vulnerabilities.

For that reason, vulnerability assessment and signature verification are
treated as separate supply-chain controls.

## Security Properties Demonstrated

- registry-backed OCI artifact
- immutable digest identification
- private/public signing key separation
- Cosign signature creation
- public-key signature verification
- negative verification of an unsigned artifact
