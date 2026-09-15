# Kubernetes Security Hardening

## Overview

This implementation demonstrates layered Kubernetes workload security using native Kubernetes controls, Calico network segmentation, vulnerability scanning, least-privilege authorization, and container runtime hardening.

The security model covers:

- Pod Security Standards
- container security contexts
- network segmentation
- image vulnerability scanning
- Kubernetes Secrets
- least-privilege RBAC
- ResourceQuota
- LimitRange
- workload isolation and validation

## Security Architecture

~~text
                    Kubernetes Cluster

                 Pod Security Admission
                         |
                         v
              Restricted Workload Policy
                         |
          +--------------+--------------+
          |                             |
          v                             v
    Hardened Pods                 RBAC Controls
          |                             |
          v                             v
   Non-root runtime              Least privilege
   Seccomp profile               namespace scope
   Read-only root FS
   Capabilities dropped
          |
          v
      Calico CNI
          |
          v
   NetworkPolicy Layer

 frontend  --->  backend  --->  database
     |                          ^
     +------- BLOCKED ----------+

          Container Images
                |
                v
             Trivy
                |
       HIGH / CRITICAL scan
~~

## Pod Security Standards

The `secure-apps` namespace was configured using the Kubernetes Restricted Pod Security profile.

Restricted workloads require controls including:

- non-root execution
- `allowPrivilegeEscalation: false`
- all Linux capabilities dropped
- approved seccomp profiles
- restricted privilege configuration

An intentionally privileged workload was rejected by admission control.

The compliant workloads use:

~~yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
~~

Container-level controls include:

~~yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop:
    - ALL
~~

Automatic ServiceAccount token mounting is disabled where Kubernetes API access is unnecessary.

## Network Segmentation

Calico provides NetworkPolicy enforcement.

Three application tiers were used:

~~text
frontend
   |
   | TCP/80
   v
backend
   |
   | TCP/5432
   v
database
~~

Validated behavior:

| Traffic path | Result |
|---|---|
| Frontend → Backend | Allowed |
| Frontend → Database | Blocked |
| Backend → Database | Allowed |
| Database → Backend | Blocked |

The database accepts traffic only from the backend namespace.

The backend accepts application traffic only from the frontend namespace.

This prevents direct lateral access between application tiers.

## Secret Handling

Database credentials are supplied through a Kubernetes Secret rather than being embedded directly in the Deployment manifest.

~~yaml
valueFrom:
  secretKeyRef:
    name: database-credentials
    key: POSTGRES_PASSWORD
~~

Secret values are intentionally excluded from this repository.

## Image Vulnerability Scanning

Trivy was used to scan container images for HIGH and CRITICAL vulnerabilities.

The process included:

- baseline image scanning
- JSON/table report generation
- cluster-wide container image discovery
- automated scanning of running workload images
- hardened image comparison

Observed comparison during validation:

~~text
nginx:latest
HIGH:     69
CRITICAL: 4
TOTAL:    73

secure-web:v1.0.0
HIGH:     36
CRITICAL: 0
TOTAL:    36
~~

Vulnerability results represent the scanner database at scan time and can change as CVEs and vendor advisories are updated.

## Hardened Container Image

The hardened web workload uses an unprivileged nginx image.

~~dockerfile
FROM nginxinc/nginx-unprivileged:1.29-alpine

COPY --chown=101:101 index.html /usr/share/nginx/html/index.html

USER 101

EXPOSE 8080
~~

Runtime validation confirmed execution as an unprivileged user.

## Cluster Image Scanner

`image-security/scan-cluster-images.sh` discovers unique images running across the Kubernetes cluster and scans them with Trivy.

Example:

~~bash
./image-security/scan-cluster-images.sh
~~

This provides a simple cluster image inventory and vulnerability assessment workflow.

## Least-Privilege RBAC

A dedicated ServiceAccount is bound to a namespace-scoped Role.

Allowed operations:

~~text
get pods
list pods
watch pods
~~

Explicit authorization testing confirmed the identity could not:

- delete Pods
- read Secrets
- create Deployments
- access Pods in unrelated namespaces

Example validation:

~~bash
kubectl auth can-i get pods \
  --as=system:serviceaccount:secure-apps:app-service-account \
  -n secure-apps
~~

Negative authorization example:

~~bash
kubectl auth can-i get secrets \
  --as=system:serviceaccount:secure-apps:app-service-account \
  -n secure-apps
~~

## Resource Protection

A ResourceQuota restricts aggregate namespace consumption.

Controls include:

- CPU requests
- CPU limits
- memory requests
- memory limits
- Pod count
- Service count

A LimitRange defines default and maximum per-container resource values.

This protects the namespace against uncontrolled resource consumption.

## Security Controls Demonstrated

| Control | Implementation |
|---|---|
| Pod admission security | Restricted Pod Security Standards |
| Non-root runtime | SecurityContext |
| Privilege escalation | Disabled |
| Linux capabilities | All dropped |
| Seccomp | RuntimeDefault |
| Root filesystem | Read-only |
| ServiceAccount token | Disabled where unnecessary |
| Network segmentation | Calico NetworkPolicy |
| Image vulnerabilities | Trivy |
| Credentials | Kubernetes Secret |
| Authorization | Namespace-scoped RBAC |
| Resource exhaustion | ResourceQuota + LimitRange |

## Validation

Inspect Pod Security labels:

~~bash
kubectl get namespace secure-apps \
  --show-labels
~~

Inspect network policies:

~~bash
kubectl get networkpolicy -A
~~

Inspect RBAC:

~~bash
kubectl get role,rolebinding,serviceaccount \
  -n secure-apps
~~

Inspect resource controls:

~~bash
kubectl get resourcequota,limitrange \
  -n secure-apps
~~

Inspect workload security:

~~bash
kubectl get pods \
  -n secure-apps \
  -o wide
~~

## Production Extensions

Further production hardening could include:

- Kyverno or Gatekeeper admission policies
- signed-image verification with Cosign
- SBOM generation
- registry admission controls
- runtime threat detection
- Kubernetes audit logging
- external secret management
- workload identity
- default-deny egress controls
- service mesh authorization policies
- CI vulnerability gates
- policy-as-code validation

## Repository Structure

~~text
kubernetes-security-hardening/
├── README.md
├── pod-security/
│   ├── secure-pod.yaml
│   └── secure-web-deployment.yaml
├── network-policies/
│   ├── frontend-app.yaml
│   ├── backend-app.yaml
│   ├── database-app.yaml
│   ├── backend-network-policy.yaml
│   └── database-network-policy.yaml
├── image-security/
│   ├── hardened-image/
│   ├── scan-cluster-images.sh
│   ├── nginx-baseline-scan.txt
│   └── hardened-image-scan.txt
├── access-control/
│   └── rbac-config.yaml
└── resource-controls/
    └── resource-controls.yaml
~~

## Skills Demonstrated

- Kubernetes security architecture
- Pod Security Standards
- container runtime hardening
- Calico NetworkPolicy
- zero-trust segmentation
- Trivy vulnerability scanning
- Kubernetes Secrets
- least-privilege RBAC
- ResourceQuota
- LimitRange
- security testing and validation
