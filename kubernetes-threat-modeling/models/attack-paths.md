# Pre-Mitigation Attack Paths

## AP-01 — Compromised Workload to Internal Services

Entry point:
Compromised vulnerable workload

Observed path:

vulnerable-pod
    |
    +--> backend-service:8080
    |
    +--> database-service:5432

Backend connectivity:
REACHABLE

Database connectivity:
REACHABLE

Risk:
Unrestricted east-west network access enables lateral movement.

Planned mitigation:
Default-deny NetworkPolicy with explicit tier-to-tier flows.

---

## AP-02 — Workload Identity to Kubernetes API

Entry point:
Mounted ServiceAccount token

Observed path:

Pod
 |
 +--> projected ServiceAccount token
 |
 +--> kubernetes.default.svc:443

API network access:
REACHABLE

API authorization result:
HTTP 403

Risk:
If a workload identity receives excessive RBAC, application compromise can become Kubernetes API compromise.

Planned mitigation:
Dedicated ServiceAccounts, least-privilege RBAC, and token minimization.

---

## AP-03 — Container to Host Boundary

Entry point:
Privileged container

Observed controls:
- privileged=true
- UID 0
- SYS_ADMIN capability
- NET_ADMIN capability
- host root mounted read-only at /host

Risk:
Privileged execution and host mounts collapse normal container isolation assumptions.

Planned mitigation:
Restricted Pod Security Admission, non-root containers, capability dropping, no hostPath.

---

## AP-04 — Service Discovery to Lateral Movement

Entry point:
Compromised workload

Observed capability:
Internal DNS resolution for backend, database, and Kubernetes API services.

Risk:
Service discovery combined with unrestricted networking improves attacker reachability.

Planned mitigation:
Network segmentation and workload-specific communication policies.
