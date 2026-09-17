# STRIDE Threat Analysis

## Spoofing

### S1 — Workload Identity Misuse
Asset:
Kubernetes ServiceAccount identity

Attack Path:
Compromised Pod -> mounted ServiceAccount token -> Kubernetes API

Baseline:
Default ServiceAccount token was automatically mounted.

Mitigations:
- dedicated workload ServiceAccounts
- token automount disabled where API access is unnecessary
- least-privilege RBAC

Residual Risk:
Workloads that legitimately require API access can still expose their identity if compromised.

### S2 — Internal Service Impersonation
Asset:
Internal services

Attack Path:
Compromised workload -> service discovery -> internal service

Mitigations:
- NetworkPolicy segmentation
- explicit tier-to-tier communication

Residual Risk:
NetworkPolicy controls reachability but does not provide cryptographic service identity.


## Tampering

### T1 — Kubernetes Resource Modification
Asset:
Application deployments and configuration

Attack Path:
Compromised identity -> Kubernetes API -> workload modification

Mitigations:
- scoped RBAC
- removal of unnecessary workload API credentials

Residual Risk:
Legitimately privileged administrators can still modify resources.

### T2 — Container Image Tampering
Asset:
Container images

Mitigation:
Handled through separate image signing and supply-chain controls.

Residual Risk:
A trusted image may still contain vulnerabilities.


## Repudiation

### R1 — Unattributed Security Activity
Asset:
Kubernetes control plane

Risk:
Security-sensitive operations may be difficult to attribute when generic workload identities are used.

Mitigations:
- workload-specific ServiceAccounts
- identity-specific RBAC

Residual Risk:
Centralized audit correlation remains necessary.


## Information Disclosure

### I1 — Direct Database Access
Asset:
PostgreSQL database

Baseline:
An unrelated workload could directly reach database-service:5432.

Mitigation:
Default-deny NetworkPolicy with explicit backend-to-database access.

Residual Risk:
A compromised backend remains an authorized database client.

### I2 — Credential Exposure
Asset:
Database credentials

Mitigations:
- credential removed from workload manifest
- Kubernetes Secret used
- restricted ServiceAccount denied Secret reads

Residual Risk:
Cluster-privileged identities retain access.

### I3 — Service Discovery
Asset:
Internal application topology

Baseline:
Backend, database, and Kubernetes API services were discoverable.

Mitigation:
Network segmentation limits useful connectivity.

Residual Risk:
Internal DNS metadata remains visible.


## Denial of Service

### D1 — Workload Resource Exhaustion
Asset:
Application availability

Mitigation:
CPU and memory requests and limits.

Residual Risk:
Distributed or node-level resource exhaustion remains possible.

### D2 — Kubernetes API Abuse
Asset:
Control plane availability

Mitigations:
- workload API token minimization
- least-privilege RBAC

Residual Risk:
Additional API Priority & Fairness and rate controls may be required.


## Elevation of Privilege

### E1 — Container Escape
Asset:
Kubernetes node

Baseline:
The vulnerable workload demonstrated:
- privileged execution
- UID 0
- SYS_ADMIN
- NET_ADMIN
- hostPath access

Mitigations:
- non-root execution
- privilege escalation disabled
- capabilities dropped
- RuntimeDefault seccomp
- hostPath removed
- Restricted Pod Security Admission

Residual Risk:
Kernel or runtime vulnerabilities can still create escape paths.

### E2 — RBAC Privilege Escalation
Asset:
Kubernetes control plane

Mitigation:
Namespace-scoped least-privilege RBAC.

Validated:
- pod reads allowed
- Secret reads denied
- deployment creation denied

Residual Risk:
Future RBAC drift can reintroduce excessive permissions.
