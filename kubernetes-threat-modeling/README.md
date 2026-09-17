# Kubernetes Threat Modeling

A Kubernetes security architecture assessment using STRIDE, trust-boundary analysis, runtime attack-path validation, and defense-in-depth mitigations.

This implementation models a three-tier application, identifies security-critical assets and trust boundaries, validates real pre-mitigation attack paths, applies Kubernetes security controls, and measures how those controls change the resulting attack surface.

## Architecture

```text
External Client
      |
      v
Frontend
      |
      v
Backend
      |
      v
PostgreSQL
```

Additional security-sensitive paths:

```text
Application Pod
      |
      v
ServiceAccount
      |
      v
Kubernetes API
```

and:

```text
Container
    |
    X
    |
Kubernetes Node
```

## Threat Modeling Methodology

The assessment uses STRIDE:

```text
S — Spoofing
T — Tampering
R — Repudiation
I — Information Disclosure
D — Denial of Service
E — Elevation of Privilege
```

Each identified threat is linked to:

```text
asset
trust boundary
attack path
pre-mitigation exposure
implemented control
residual exposure
priority
```

## Critical Assets

The analysis identifies:

```text
PostgreSQL application data
Database credentials
Kubernetes ServiceAccount identities
Kubernetes API access
Application deployments
Kubernetes node
Internal service topology
Application availability
```

## Trust Boundaries

### External -> Frontend

Primary concerns:

```text
untrusted clients
application exploitation
spoofing
denial of service
```

### Frontend -> Backend

Primary concerns:

```text
lateral movement
service impersonation
compromised frontend workloads
```

### Backend -> Database

Primary concerns:

```text
unauthorized database access
credential compromise
information disclosure
tampering
```

### Workload -> Kubernetes API

Primary concerns:

```text
ServiceAccount token theft
RBAC escalation
control-plane access
```

### Container -> Node

Primary concerns:

```text
privileged execution
dangerous Linux capabilities
hostPath access
container escape
```

## Pre-Mitigation Security Baseline

The initial environment intentionally represented a weak internal-trust model.

Observed conditions included:

```text
No workload NetworkPolicies
Default ServiceAccount usage
Automatic ServiceAccount token mounting
Unrestricted east-west connectivity
Direct database reachability
Direct backend reachability
Privileged attacker workload
UID 0 execution
SYS_ADMIN capability
NET_ADMIN capability
Host root filesystem visibility
```

This created a measurable baseline before security controls were introduced.

## Attack Path 1 — Lateral Movement to Backend

```text
Compromised Workload
        |
        v
backend-service:8080
```

### Before

An unrelated workload could reach the backend directly.

### Mitigation

```text
default-deny NetworkPolicy
+
explicit frontend-to-backend allow policy
```

### After

```text
Unrelated workload -> Backend     BLOCKED
Frontend -> Backend               ALLOWED
```

The security control therefore blocked unauthorized communication without breaking the legitimate application path.

## Attack Path 2 — Lateral Movement to Database

```text
Compromised Workload
        |
        v
database-service:5432
```

### Before

The database was directly reachable from an unrelated workload.

### Mitigation

```text
default-deny NetworkPolicy
+
explicit backend-to-database allow policy
```

### After

```text
Unrelated workload -> Database    BLOCKED
Backend -> Database               ALLOWED
```

## Attack Path 3 — Workload Identity Abuse

```text
Compromised Pod
       |
       v
Mounted ServiceAccount Token
       |
       v
Kubernetes API
```

The baseline workload automatically received a Kubernetes ServiceAccount token.

The hardened application replaces this model with:

```text
dedicated frontend ServiceAccount
dedicated backend ServiceAccount
automountServiceAccountToken=false
least-privilege RBAC for API-enabled identities
```

The restricted security identity is intentionally allowed only to:

```text
get pods
list pods
```

It cannot:

```text
read Secrets
create Deployments
```

## Attack Path 4 — Container-to-Host Escalation

The intentionally vulnerable workload demonstrated the effect of combining:

```text
privileged=true
UID 0
SYS_ADMIN
NET_ADMIN
hostPath /
```

Conceptually:

```text
Privileged Container
      |
      +--> root
      +--> powerful Linux capabilities
      +--> host filesystem
      |
      v
Node Trust Boundary
```

The hardened workload instead uses:

```text
runAsNonRoot
explicit non-root UID
allowPrivilegeEscalation=false
capabilities.drop=ALL
RuntimeDefault seccomp
no hostPath
```

A separate Restricted Pod Security namespace verifies that privileged workloads are rejected at admission.

## Network Segmentation

The network security model follows default deny.

```text
                 ALLOW
Frontend ----------------> Backend
                              |
                              | ALLOW
                              v
                           Database
```

Everything else is denied unless explicitly required.

The policies include:

```text
default-deny ingress
default-deny egress
DNS access
frontend -> backend
backend -> database
```

This replaces implicit namespace trust with explicit application communication paths.

## Workload Identity

Dedicated ServiceAccounts are used for the application tiers.

```text
frontend -> frontend-sa
backend  -> backend-sa
```

Neither workload requires Kubernetes API access, so ServiceAccount credential automounting is disabled.

This reduces the usefulness of a compromised application container as a control-plane attack foothold.

## Least-Privilege RBAC

The restricted test identity receives only:

```yaml
resources:
- pods

verbs:
- get
- list
```

Validation demonstrates:

```text
Get pods               ALLOWED
Read Secrets           DENIED
Create Deployments     DENIED
```

## Pod Security

The hardened workload demonstrates:

```text
non-root execution
RuntimeDefault seccomp
capability dropping
privilege escalation prevention
resource requests
resource limits
no hostPath
```

Restricted Pod Security Admission prevents intentionally privileged workload specifications from entering the protected namespace.

## STRIDE Findings

### Spoofing

Threats:

```text
ServiceAccount identity theft
Internal service impersonation
```

Controls:

```text
dedicated ServiceAccounts
token minimization
network segmentation
```

### Tampering

Threats:

```text
unauthorized workload modification
container image tampering
```

Controls:

```text
least-privilege RBAC
reduced workload API access
container supply-chain controls
```

### Repudiation

Threat:

```text
insufficient attribution of security-sensitive operations
```

Controls:

```text
workload-specific identity
API audit capability in the broader platform architecture
```

### Information Disclosure

Threats:

```text
direct database access
Secret exposure
service discovery
```

Controls:

```text
network segmentation
Secret permissions
credential removal from manifests
```

### Denial of Service

Threats:

```text
CPU exhaustion
memory exhaustion
API abuse
```

Controls:

```text
resource requests
resource limits
workload API credential minimization
```

### Elevation of Privilege

Threats:

```text
container escape
privileged workload execution
RBAC escalation
```

Controls:

```text
non-root containers
capability dropping
seccomp
Restricted Pod Security
least-privilege RBAC
```

## Before vs After

```text
CONTROL / PATH                     BEFORE       AFTER

Unrelated -> Backend               Reachable    Blocked
Unrelated -> Database              Reachable    Blocked

Frontend -> Backend                Reachable    Allowed
Backend -> Database                Reachable    Allowed

Frontend API token                 Mounted      Disabled
Backend API token                  Mounted      Disabled

Privileged attacker workload       Allowed      Denied in restricted namespace
Host filesystem exposure           Present      Removed
Dangerous capabilities             Present      Dropped

restricted-sa get pods             N/A          Allowed
restricted-sa get Secrets          N/A          Denied
restricted-sa create deployment    N/A          Denied
```

## Residual Risk

Threat modeling does not assume that controls completely eliminate risk.

Remaining risks include:

```text
compromised authorized backend workloads
container runtime vulnerabilities
kernel vulnerabilities
vulnerabilities inside trusted images
privileged cluster administrators
future RBAC drift
cluster-level Secret access
service impersonation without mTLS
distributed denial of service
external credential compromise
```

These risks are explicitly retained in the risk register instead of being hidden by a simple secure/insecure classification.

## Defense in Depth

The architecture applies controls across multiple layers.

```text
Identity
   |
   +-- dedicated ServiceAccounts
   +-- token minimization
   +-- least-privilege RBAC

Network
   |
   +-- default deny
   +-- frontend -> backend
   +-- backend -> database

Workload
   |
   +-- non-root
   +-- capability dropping
   +-- seccomp
   +-- resource limits

Admission
   |
   +-- Restricted Pod Security

Data
   |
   +-- credential isolation
   +-- database segmentation

Supply Chain
   |
   +-- image verification controls
```

## Repository Structure

```text
kubernetes-threat-modeling/
├── README.md
├── .gitignore
├── config/
│   └── kind.yaml
├── manifests/
│   ├── ecommerce-stack.yaml
│   ├── network-policies.yaml
│   ├── privileged-denied.yaml
│   ├── restricted-namespace.yaml
│   ├── secure-application-patch.yaml
│   ├── secure-pod.yaml
│   └── serviceaccounts-rbac.yaml
├── models/
│   ├── asset-inventory.md
│   ├── attack-paths.md
│   ├── data-flows.md
│   ├── defense-in-depth.md
│   ├── final-risk-register.csv
│   ├── stride-analysis.md
│   ├── threat-register.csv
│   ├── threat-register-mitigated.csv
│   └── trust-boundaries.md
├── scripts/
│   ├── baseline-analysis.sh
│   ├── stride-summary.sh
│   └── validate-mitigations.sh
└── evidence/
    ├── pre-mitigation analysis
    ├── attack-path evidence
    ├── mitigation validation
    ├── STRIDE summary
    ├── final risk assessment
    └── final threat-model report
```

## Security Engineering Principles Demonstrated

```text
Trust boundaries before controls
Threat-driven architecture
Attack-path validation
Default-deny networking
Least privilege
Identity minimization
Secure-by-default workloads
Negative security testing
Defense in depth
Residual-risk documentation
```

## Production Extensions

A production implementation could extend this model with:

```text
centralized Kubernetes API auditing
SIEM correlation
service mesh mTLS
Vault or external secrets management
runtime threat detection
policy-as-code admission
KMS-backed Secret encryption
continuous RBAC analysis
node hardening
image signing
vulnerability scanning
API Priority & Fairness
security alerting
```

## Key Takeaway

The main outcome is not simply a collection of Kubernetes security controls.

The implementation demonstrates the full security-engineering loop:

```text
Architecture
     |
     v
Assets
     |
     v
Trust Boundaries
     |
     v
Threats
     |
     v
Attack Paths
     |
     v
Runtime Validation
     |
     v
Mitigations
     |
     v
Re-Testing
     |
     v
Residual Risk
```

That turns Kubernetes hardening from a checklist into a threat-driven security architecture.
