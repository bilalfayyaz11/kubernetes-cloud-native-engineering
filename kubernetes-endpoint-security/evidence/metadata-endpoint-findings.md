# EC2 Metadata Endpoint Protection

## Threat

Amazon EC2 Instance Metadata Service is available through the
link-local address:

`169.254.169.254`

A compromised workload should not automatically inherit network
reachability to host/cloud credential endpoints.

## Existing Cloud Control

The host baseline returned HTTP 401 for unauthenticated IMDS requests,
indicating that IMDSv2 authentication is required.

IMDSv2 reduces exposure but does not replace workload-level network
segmentation.

## Kubernetes Control

Namespace:

`endpoint-security`

NetworkPolicy:

`restrict-sensitive-egress`

The policy:

- selects workloads in the protected namespace
- preserves cluster DNS
- preserves ordinary IPv4 egress
- excludes the complete IPv4 link-local range `169.254.0.0/16`
- therefore blocks EC2 IMDS at `169.254.169.254`

## Validation

Before policy:

- metadata endpoint exit code: 1
- metadata HTTP status: unreachable
- IMDSv2 token endpoint exit code: 1
- IMDSv2 token HTTP status: unreachable

After policy:

- metadata endpoint exit code: 1
- metadata HTTP status: unreachable
- IMDSv2 token endpoint exit code: 1
- IMDSv2 token HTTP status: unreachable

Hardened workload:

- metadata endpoint exit code: 7
- metadata HTTP status: 000

No metadata values, IAM role names, credentials, or IMDSv2 token bodies
were printed or stored during validation.

## Defense in Depth

The hardened workload additionally uses:

- non-root execution
- RuntimeDefault seccomp
- all Linux capabilities dropped
- privilege escalation disabled
- read-only root filesystem
- dedicated writable temporary volume
- disabled automatic ServiceAccount token mounting

The metadata restriction is enforced by networking rather than DNS
rewriting, so applications cannot bypass the control by connecting
directly to the metadata IP address.
