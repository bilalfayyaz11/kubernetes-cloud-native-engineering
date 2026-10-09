# Kubernetes Endpoint Security

A defense-in-depth implementation for protecting Kubernetes control-plane access and preventing workloads from reaching cloud instance metadata.

The implementation combines host-level API filtering, Kubernetes NetworkPolicy, workload hardening, runtime validation, and adversarial connectivity testing.

## Security Objectives

- Restrict Kubernetes API access at the host firewall
- Deny API traffic that does not match trusted network sources
- Prevent workloads from accessing EC2 Instance Metadata Service
- Block both metadata retrieval and IMDSv2 token acquisition
- Preserve Kubernetes DNS and service connectivity
- Preserve legitimate outbound HTTPS connectivity
- Disable unnecessary ServiceAccount credential mounting
- Enforce non-root workload execution
- Enforce a read-only root filesystem
- Validate controls against runtime behavior rather than configuration alone

## Architecture

    Trusted Administration
             |
             v
    +-----------------------+
    |    K8S_API_GUARD      |
    |    TCP/6443 Filter    |
    +-----------+-----------+
                |
                v
    +-----------------------+
    |    Kubernetes API     |
    |       K3s Server      |
    +-----------------------+

    Kubernetes Workload
             |
             v
    +-----------------------+
    |     NetworkPolicy     |
    |   Egress Enforcement  |
    +-----------+-----------+
                |
                +------> DNS / Kubernetes Services
                |
                +------> Normal HTTPS Egress
                |
                X
         169.254.0.0/16
                |
                X
    +-----------------------+
    | EC2 Metadata / IMDS   |
    +-----------------------+

## Kubernetes API Protection

A dedicated host firewall chain named `K8S_API_GUARD` protects TCP port `6443`.

The rule set permits:

- loopback traffic
- established and related connections
- Kubernetes Pod and Service network ranges required by the cluster
- private VPC traffic required by the environment
- the explicitly identified administrative source

Traffic reaching the end of the chain without matching an allowed source is logged and dropped.

This provides an additional network enforcement layer around Kubernetes API authentication and authorization.

The current environment permits the private VPC CIDR for cluster compatibility. A production deployment should narrow trusted source ranges further where the network architecture allows it.

## EC2 Metadata Protection

Workloads in the protected namespace are governed by an egress NetworkPolicy.

The policy permits required network connectivity while excluding the link-local range:

    169.254.0.0/16

This prevents protected workloads from accessing the EC2 Instance Metadata Service at:

    169.254.169.254

Validation covers both metadata retrieval and IMDSv2 token acquisition.

The EC2 IMDSv2 requirement provides an additional infrastructure-side protection layer, while Kubernetes NetworkPolicy provides workload-level isolation.

## Hardened Workload

The validation workload uses a restricted security context including:

- automatic ServiceAccount token mounting disabled
- non-root execution
- explicit UID/GID
- privilege escalation disabled
- all Linux capabilities dropped
- RuntimeDefault seccomp profile
- read-only root filesystem
- dedicated writable temporary storage

This reduces both credential exposure and post-compromise capability.

## NetworkPolicy Strategy

The egress policy is focused on protecting the cloud metadata endpoint without unnecessarily breaking application connectivity.

Normal outbound connectivity is preserved while the link-local metadata range is excluded.

DNS traffic remains available so workloads can resolve Kubernetes Services and external destinations.

## Runtime Validation

Controls were validated against runtime behavior rather than assuming that configuration alone implied enforcement.

| Validation | Result |
| --- | --- |
| Kubernetes API health | PASS |
| API firewall attached | PASS |
| Default untrusted API rule | DROP |
| Anonymous node-data access | DENIED |
| NetworkPolicy enforcement | OBSERVED |
| EC2 metadata access | BLOCKED |
| IMDSv2 token acquisition | BLOCKED |
| Hardened workload metadata access | BLOCKED |
| Kubernetes service discovery | PASS |
| Ordinary HTTPS egress | PASS |
| ServiceAccount token automount | DISABLED |
| Non-root execution | VERIFIED |
| Read-only root filesystem | VERIFIED |
| Automated validation | PASS |

## Control-Plane Availability Validation

Firewall enforcement was tested against cluster availability rather than treating security and reliability as separate concerns.

The API firewall was refined to permit the Kubernetes Pod and Service network ranges required by the environment.

After recovery and revalidation, the core system workloads were healthy:

    CoreDNS                 1/1 Running
    Metrics Server          1/1 Running
    Local Path Provisioner  1/1 Running

The Kubernetes control-plane node remained Ready.

Kubernetes service discovery returned the expected unauthenticated API response, while ordinary outbound HTTPS connectivity remained functional.

This demonstrates an important production security principle: a control must enforce the intended boundary without unnecessarily disrupting legitimate system behavior.

## Metadata Validation

The final validation confirmed:

    EC2 metadata endpoint      BLOCKED
    IMDSv2 token endpoint      BLOCKED

Both metadata retrieval and token acquisition attempts from the protected workload failed.

## API Firewall Validation

The final API firewall contains explicit trusted-source rules followed by logging and a default TCP/6443 drop rule.

The enforcement model includes:

- loopback allowance
- established connection allowance
- Pod CIDR allowance
- Service CIDR allowance
- private VPC allowance
- explicit administrative source allowance
- denied-request logging
- final API DROP rule

This provides network-layer protection in addition to Kubernetes authentication and authorization.

## Adversarial Validation

Testing included:

- anonymous Kubernetes API requests
- API firewall rule inspection
- Kubernetes API port scanning
- metadata requests from protected workloads
- IMDSv2 token requests
- comparison with a separate adversarial namespace
- DNS and Kubernetes Service connectivity
- ordinary external HTTPS connectivity
- ServiceAccount token inspection
- runtime UID verification
- root filesystem write testing

The temporary adversarial namespace was removed after validation.

## Automated Security Gate

The `endpoint-security-test.sh` script provides repeatable verification of the primary controls.

The final execution produced:

    PASS  Kubernetes API is healthy
    PASS  API firewall chain attached
    PASS  Untrusted API traffic reaches DROP rule
    PASS  EC2 metadata endpoint blocked from protected workload
    PASS  IMDSv2 token endpoint blocked
    PASS  Metadata protection NetworkPolicy present
    PASS  Automatic ServiceAccount token disabled
    PASS  Workload runs as non-root UID 10001
    PASS  Root filesystem is read-only

    Failures: 0
    OVERALL RESULT: PASS

The validator returns a non-zero exit status when a required control fails, making the checks suitable for automated security verification workflows.

## Defense in Depth

| Layer | Protection |
| --- | --- |
| Host firewall | Restricts Kubernetes API network access |
| Kubernetes authentication | Rejects unauthorized API requests |
| NetworkPolicy | Blocks workload access to link-local metadata |
| IMDSv2 | Adds infrastructure-side metadata protection |
| ServiceAccount configuration | Prevents unnecessary credential mounting |
| SecurityContext | Reduces workload privileges |
| Seccomp | Restricts syscall exposure |
| Runtime tests | Confirms controls behave as intended |

## Repository Structure

    kubernetes-endpoint-security/
    ├── README.md
    ├── manifests/
    │   ├── api-test-pod.yaml
    │   ├── block-ec2-metadata.yaml
    │   └── secure-endpoint-pod.yaml
    ├── scripts/
    │   └── endpoint-security-test.sh
    └── evidence/
        ├── api-endpoint-findings.md
        ├── api-firewall-validation.txt
        ├── api-port-scan.txt
        ├── endpoint-security-report.md
        ├── endpoint-security-summary.json
        ├── endpoint-security-test-results.txt
        ├── hardened-workload-security-context.json
        ├── metadata-endpoint-findings.md
        ├── metadata-network-policy.yaml
        └── network-policy-runtime-rules.txt

## Skills Demonstrated

Kubernetes security, K3s, NetworkPolicy, Linux firewalling, iptables, cloud metadata protection, EC2 IMDSv2, workload hardening, ServiceAccount security, seccomp, least-privilege design, runtime security validation, adversarial testing, troubleshooting, and security evidence generation.
