# Container SBOM Analysis

## Images

| Image | Repository Digest |
|---|---|
| `nginx:1.28-alpine` | `nginx@sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236` |
| `python:3.12-slim` | `python@sha256:f77ac9e44ae96ef2c90b8053ea08c31f8be030f824196b0ae4db6d462c84e51f` |

## Generated Formats

Each image was analyzed with Syft and exported as:

- SPDX JSON
- CycloneDX JSON
- Human-readable package inventory

## Component Counts

| Image | SPDX Packages | CycloneDX Components |
|---|---:|---:|
| `nginx:1.28-alpine` | 73 | 1315 |
| `python:3.12-slim` | 96 | 2757 |

## Why Multiple SBOM Formats Matter

SPDX and CycloneDX provide machine-readable software inventories suitable
for vulnerability management, compliance workflows, artifact analysis,
and automated supply-chain controls.

The table representation provides a fast human-readable inventory during
interactive investigation.

## Security Value

An SBOM establishes visibility into the software components contained
inside a container image.

It enables later stages of the supply-chain workflow to correlate image
contents with vulnerability data and verify exactly which artifact was
assessed before deployment.

## Image Identity

Repository digests were captured where available so analysis can be tied
to immutable image content instead of relying only on mutable tags.

## Findings

The two reference images contain different dependency sets and package
inventories.

The package count itself is not a vulnerability score. A larger
dependency inventory simply represents a larger set of components that
must be tracked and assessed through later vulnerability and provenance
controls.
