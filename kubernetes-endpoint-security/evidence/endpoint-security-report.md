# Kubernetes Cluster Endpoint Security Assessment

## Scope

This assessment validates controls protecting:

- the Kubernetes API endpoint
- EC2 Instance Metadata Service
- Pod egress
- workload credentials
- workload execution context

## Environment

The Kubernetes cluster runs on Amazon EC2.

Kubernetes API endpoint:

`https://127.0.0.1:6443`

## Kubernetes API Protection

TCP/6443 is protected using the host-level
`K8S_API_GUARD` firewall chain.

The control permits required trusted traffic and terminates other API
traffic at an explicit DROP rule.

Firewall attached:

`1`

Default API DROP rule:

`1`

Anonymous node-data request HTTP status:

`401`

Authentication and authorization remain separate from network
restriction. Network controls reduce endpoint exposure while Kubernetes
authorization controls what an authenticated identity may perform.

## EC2 Metadata Protection

The protected namespace uses an egress NetworkPolicy that excludes:

`169.254.0.0/16`

This includes EC2 IMDS:

`169.254.169.254`

Observed protected-workload metadata result:

- curl exit code: 1
- HTTP status: unreachable

Observed IMDSv2 token endpoint result:

- curl exit code: 1
- HTTP status: unreachable

No metadata payloads, IAM role names, credentials, or IMDSv2 tokens were
printed or stored.

## Availability Validation

Security controls were tested for unintended availability impact.

Kubernetes Service:

`000`

External HTTPS:

`000`

This distinguishes targeted metadata isolation from indiscriminate
egress blocking.

## Workload Hardening

The hardened validation workload implements:

- non-root execution
- RuntimeDefault seccomp
- dropped Linux capabilities
- disabled privilege escalation
- read-only root filesystem
- explicit writable temporary storage
- disabled automatic ServiceAccount token mounting

## Adversarial Validation

The assessment includes a separate control namespace to distinguish
namespace-scoped NetworkPolicy behavior from infrastructure-level
metadata restrictions.

Control namespace IMDS result:

- curl exit code: 0
- HTTP status: 401

If the control namespace can reach IMDS while the protected namespace
cannot, the result directly demonstrates Kubernetes NetworkPolicy
enforcement.

If both are blocked, the environment contains an additional
infrastructure/CNI-level restriction and the report does not falsely
attribute all protection to the namespace policy.

## Automated Validation

Automated security validator exit code:

`0`

The validator checks:

- Kubernetes API health
- API firewall enforcement
- metadata endpoint blocking
- IMDSv2 token endpoint blocking
- NetworkPolicy presence
- ServiceAccount token suppression
- non-root execution
- read-only root filesystem

## Security Model

Endpoint protection uses multiple independent layers:

1. cloud metadata configuration
2. host firewall API restrictions
3. Kubernetes authentication and authorization
4. NetworkPolicy egress isolation
5. workload security context
6. ServiceAccount credential minimization
7. repeatable validation

This avoids relying on a single security control for cluster endpoint
protection.
