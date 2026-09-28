# Signed Image Admission Enforcement

## Policy Engine

Kyverno ImageValidatingPolicy

## Scope

Namespace:

`supply-chain-demo`

Registry pattern:

`localhost:5001/*`

## Trust Model

Images must:

1. use an immutable digest
2. carry a valid Cosign signature
3. validate against the trusted `cosign.pub` key

## Signed Artifact

`localhost:5001/secure-app@sha256:<IMAGE_DIGEST>`

Admission result:

**ALLOWED**

## Unsigned Artifact

`localhost:5001/unsigned-nginx@sha256:<IMAGE_DIGEST>`

Admission result:

**DENIED**

## Enforcement Model

The admission controller performs real cryptographic signature
verification against the OCI registry.

Image naming conventions are not treated as evidence of trust.

## Registry

The environment uses an isolated local OCI registry for reproducible
testing.

The registry is intentionally HTTP-only for the local demonstration,
therefore the Kyverno policy explicitly allows insecure registry
transport.

Production registries should use TLS.

## Security Result

The workflow proves that possession of an image reference alone is not
sufficient for deployment.

The artifact must also possess a valid signature created by the trusted
signing identity.
