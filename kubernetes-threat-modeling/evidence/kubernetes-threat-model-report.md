# Kubernetes Threat Model Report

## Executive Summary

This assessment evaluates a three-tier Kubernetes application using the STRIDE methodology.

The analysis focuses on:

- workload identity
- Kubernetes API exposure
- east-west network movement
- database access
- container-to-host boundaries
- privilege escalation
- availability
- residual risk

The environment was assessed in both pre-mitigation and post-mitigation states.

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

Security-sensitive control-plane path:

```text
Application Pod
      |
      v
ServiceAccount
      |
      v
Kubernetes API
```

Container isolation boundary:

```text
Container
    |
    X
    |
Kubernetes Node
```

## Critical Assets

- PostgreSQL application data
- database credentials
- Kubernetes ServiceAccount identities
- Kubernetes API access
- workload configuration
- Kubernetes node
- internal service topology
- application availability

## Trust Boundaries

### External -> Frontend
Trust Level:
Untrusted

Primary Threats:
- spoofing
- application exploitation
- denial of service

### Frontend -> Backend
Trust Level:
Partially trusted

Primary Threats:
- lateral movement
- service impersonation

### Backend -> Database
Trust Level:
High-value internal boundary

Primary Threats:
- unauthorized access
- credential compromise
- information disclosure

### Workload -> Kubernetes API
Trust Level:
Privileged control-plane boundary

Primary Threats:
- ServiceAccount theft
- RBAC escalation

### Container -> Host
Trust Level:
Strong isolation boundary

Primary Threats:
- privileged execution
- hostPath abuse
- dangerous capabilities
- container escape

## Pre-Mitigation Findings

Observed conditions:

- no workload NetworkPolicies
- automatic ServiceAccount token mounting
- use of default ServiceAccount
- unrestricted east-west connectivity
- backend reachable from unrelated workload
- database reachable from unrelated workload
- privileged root attacker workload
- SYS_ADMIN capability
- NET_ADMIN capability
- host root filesystem mounted inside attacker pod

## Attack Paths

### AP-01 — Lateral Movement to Backend

```text
Compromised Workload
        |
        v
backend-service:8080
```

Before:
Reachable

After:
Blocked for unrelated workload

Control:
Default-deny + frontend-to-backend NetworkPolicy

### AP-02 — Lateral Movement to Database

```text
Compromised Workload
        |
        v
database-service:5432
```

Before:
Reachable

After:
Blocked for unrelated workload

Control:
Default-deny + backend-to-database NetworkPolicy

### AP-03 — Workload Identity Abuse

```text
Compromised Pod
       |
       v
ServiceAccount Token
       |
       v
Kubernetes API
```

Before:
Token automatically mounted

After:
Token automount disabled for frontend and backend workloads

Control:
Dedicated ServiceAccounts + least-privilege RBAC

### AP-04 — Container-to-Host Escalation

```text
Privileged Container
      |
      +-- root
      +-- SYS_ADMIN
      +-- NET_ADMIN
      +-- hostPath /
      |
      v
Kubernetes Node
```

Before:
Boundary weakened by privileged workload configuration

After:
- non-root workload
- capabilities dropped
- privilege escalation disabled
- RuntimeDefault seccomp
- no hostPath
- privileged workload rejected in restricted namespace

## STRIDE Summary

### Spoofing
Threats:
- workload identity theft
- service impersonation

Controls:
- dedicated ServiceAccounts
- token minimization
- NetworkPolicy segmentation

### Tampering
Threats:
- workload modification
- image modification

Controls:
- scoped RBAC
- reduced workload API access
- separate image verification controls

### Repudiation
Threat:
- poor attribution of security-sensitive actions

Controls:
- workload-specific identities

Additional Requirement:
Centralized Kubernetes API auditing

### Information Disclosure
Threats:
- direct database access
- credential exposure
- internal service discovery

Controls:
- network segmentation
- Secret access restrictions
- credential removal from manifests

### Denial of Service
Threats:
- resource exhaustion
- API abuse

Controls:
- resource requests
- resource limits
- workload API access minimization

### Elevation of Privilege
Threats:
- container escape
- RBAC escalation

Controls:
- non-root containers
- dropped capabilities
- seccomp
- Restricted Pod Security
- least-privilege RBAC

## Mitigation Validation

Validated outcomes:

```text
Unrelated workload -> Backend       BLOCKED
Unrelated workload -> Database      BLOCKED

Frontend -> Backend                 ALLOWED
Backend -> Database                 ALLOWED

Frontend ServiceAccount token       NOT AUTOMOUNTED
Backend ServiceAccount token        NOT AUTOMOUNTED

restricted-sa get pods              ALLOWED
restricted-sa get Secrets           DENIED
restricted-sa create deployments    DENIED

Privileged workload                 DENIED
Secure workload hostPath            ABSENT
Secure workload privilege           DISABLED
Secure workload capabilities        DROPPED
```

## Residual Risk

Remaining risks include:

- compromised authorized backend workloads
- vulnerable container runtime or kernel
- vulnerabilities inside trusted images
- highly privileged cluster administrators
- RBAC drift
- cluster-level Secret access
- service impersonation without mTLS
- distributed denial-of-service
- external credential compromise

## Defense-in-Depth Controls

### Identity
- dedicated ServiceAccounts
- token minimization
- least-privilege RBAC

### Network
- default deny
- frontend-to-backend allow path
- backend-to-database allow path

### Workload
- non-root execution
- capability dropping
- privilege escalation disabled
- resource limits
- seccomp

### Admission
- Restricted Pod Security Admission

### Data
- credentials excluded from manifests
- database network isolation

### Supply Chain
- image verification handled through separate controls

## Recommended Extensions

For production:

- Kubernetes API audit logging
- SIEM integration
- service mesh mTLS
- Vault or external secrets management
- policy-as-code admission
- runtime threat detection
- Secret encryption at rest
- continuous RBAC review
- node hardening
- image signing
- vulnerability scanning
- API Priority & Fairness
- security alerting

## Conclusion

The primary security improvement came from replacing implicit internal trust with explicit controls.

The architecture moved from:

```text
open workload
    |
    +--> internal services
    +--> Kubernetes API identity
    +--> host exposure
```

to:

```text
workload
    |
    +--> explicit identity
    +--> least privilege
    +--> segmented network paths
    +--> admission enforcement
    +--> constrained runtime permissions
```

The final design preserves required application communication while significantly reducing lateral movement, privilege escalation, credential exposure, and container escape attack paths.
