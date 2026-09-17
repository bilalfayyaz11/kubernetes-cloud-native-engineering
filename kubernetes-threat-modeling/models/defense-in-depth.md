# Kubernetes Defense-in-Depth Model

## Identity Layer

Controls:

- dedicated ServiceAccounts
- ServiceAccount token automount disabled where API access is unnecessary
- namespace-scoped least-privilege RBAC

Threats reduced:

- token theft
- workload identity abuse
- excessive API permissions

## Network Layer

Controls:

- default-deny ingress and egress
- frontend-to-backend allow rule
- backend-to-database allow rule
- scoped DNS access

Threats reduced:

- lateral movement
- direct database reachability
- arbitrary east-west traffic

## Workload Layer

Controls:

- non-root execution
- RuntimeDefault seccomp
- privilege escalation disabled
- Linux capabilities dropped
- resource requests and limits
- no hostPath in hardened workload

Threats reduced:

- privilege escalation
- container-to-host boundary collapse
- resource exhaustion

## Admission Layer

Control:

Restricted Pod Security Admission

Threats reduced:

- privileged workloads
- unsafe security contexts

## Data Layer

Controls:

- database credentials stored outside workload manifests
- direct network access limited to backend tier

Threats reduced:

- credential disclosure
- unauthorized database access

## Residual Risks

Controls reduce attack paths but do not eliminate all risk.

Remaining concerns include:

- application vulnerabilities
- vulnerable dependencies
- compromised signed images
- Kubernetes control-plane compromise
- node-level vulnerabilities
- credential compromise outside Kubernetes
- denial-of-service beyond configured resource controls
