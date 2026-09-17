# Kubernetes Trust Boundary Model

## Architecture

External Client
    |
    v
Frontend Service
    |
    v
Frontend Pods
    |
    v
Backend Service
    |
    v
Backend Pods
    |
    v
Database Service
    |
    v
PostgreSQL Pod

## Trust Boundary 1 — External to Frontend

Source:
External client

Destination:
Frontend service / frontend workload

Trust level:
Untrusted

Primary risks:
- spoofed clients
- malicious input
- denial of service
- application-layer exploitation

## Trust Boundary 2 — Frontend to Backend

Source:
Frontend workload

Destination:
Backend service

Trust level:
Partially trusted

Primary risks:
- compromised frontend workload
- unauthorized east-west access
- service impersonation
- lateral movement

## Trust Boundary 3 — Backend to Database

Source:
Backend workload

Destination:
PostgreSQL service

Trust level:
High-value internal boundary

Primary risks:
- credential theft
- direct database access
- data disclosure
- unauthorized modification

## Trust Boundary 4 — Workload to Kubernetes API

Source:
Pods and ServiceAccounts

Destination:
Kubernetes API server

Trust level:
Privileged control-plane boundary

Primary risks:
- stolen ServiceAccount token
- excessive RBAC permissions
- workload-to-control-plane escalation

## Trust Boundary 5 — Container to Node

Source:
Container runtime workload

Destination:
Host/node operating system

Trust level:
Strong isolation boundary

Primary risks:
- privileged containers
- hostPath mounts
- dangerous Linux capabilities
- container escape

## Current Baseline

No workload NetworkPolicies are currently applied.

No dedicated application ServiceAccounts are currently assigned.

No namespace-level Pod Security Admission policy is currently enforced.

Default ServiceAccount token behavior remains part of the baseline.

This intentionally represents a pre-mitigation state for threat analysis.
