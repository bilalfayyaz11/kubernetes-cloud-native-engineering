# Kubernetes Network Policy Isolation

## Overview

This implementation demonstrates Kubernetes east-west traffic segmentation using Calico NetworkPolicy enforcement.

A Kubernetes control plane was built from a fresh Ubuntu environment and configured with a NetworkPolicy-capable Calico CNI. Development and production workloads were then isolated using a default-deny security model with narrowly scoped ingress and egress exceptions.

The implementation demonstrates:

- Kubernetes cluster bootstrap with kubeadm
- containerd CRI configuration
- Calico CNI deployment
- NetworkPolicy enforcement verification
- namespace-based segmentation
- default-deny ingress controls
- workload identity through Kubernetes labels
- podSelector and namespaceSelector
- controlled client-to-web communication
- controlled web-to-database communication
- cross-namespace least-privilege access
- egress restrictions
- explicit CoreDNS access
- advanced matchExpressions selectors
- automated ALLOW/DENY validation
- policy inspection and troubleshooting
- configuration export
- repeatable security validation

---

## Architecture

~~text
                         Kubernetes Cluster
                                |
               +----------------+----------------+
               |                                 |
               v                                 v
        development                         production
        namespace                           namespace
               |                                 |
      Default Deny Ingress               Default Deny Ingress
               |                                 |
       +-------+-------+                 +-------+-------+
       |               |                 |               |
       v               v                 v               v
   test-client      web-app           test-client      web-app
                       |                                   X
                       |
                       | TCP/3306
                       v
                   database
                       |
                       |
                       | Controlled Cross-Namespace
                       | TCP/3306
                       v
                production/database
~~

The resulting model permits only explicitly required communication paths.

---

## Environment

The environment uses:

~~text
Ubuntu 24.04
Kubernetes 1.36
kubeadm
kubelet
kubectl
containerd
crictl
Calico
CoreDNS
BusyBox
nginx
~~

The host initially contained no active Kubernetes cluster or CNI configuration.

---

## Kubernetes Bootstrap

The Kubernetes control plane was initialized with kubeadm using containerd as the CRI runtime.

System preparation included:

- swap disabled
- `overlay` kernel module
- `br_netfilter` kernel module
- IPv4 forwarding
- bridge traffic processing
- systemd cgroups for containerd
- Kubernetes package installation
- crictl runtime configuration

Because the environment contains a single node, the control-plane scheduling taint was removed to permit application workloads.

---

## Calico Network Policy Enforcement

Calico was deployed through the Tigera Operator.

The environment verifies:

~~text
Calico availability
Calico degradation status
Calico progression status
NetworkPolicy API availability
CoreDNS health
Node readiness
~~

NetworkPolicy resources only provide actual traffic isolation when the active CNI implements policy enforcement.

Calico health was therefore verified before applying segmentation controls.

---

## Namespace Segmentation

Two isolated application namespaces are used:

~~text
development
production
~~

Namespace labels provide identity for cross-namespace selectors.

### Development

~~yaml
environment: dev
name: development
team: backend
~~

### Production

~~yaml
environment: prod
name: production
team: backend
~~

This allows policies to reference namespace identity rather than depending on Pod IP addresses.

---

## Workload Model

Each namespace contains three workload identities.

### Development

~~text
web-app
  app=web
  tier=frontend
  environment=dev
  access-level=standard

database
  app=db
  tier=backend
  environment=dev
  access-level=restricted

test-client
  app=client
  tier=testing
  environment=dev
  access-level=testing
~~

### Production

~~text
web-app
  app=web
  tier=frontend
  environment=prod

database
  app=db
  tier=backend
  environment=prod

test-client
  app=client
  tier=testing
  environment=prod
~~

---

## Lightweight Database Listeners

The database targets use lightweight TCP listeners on port `3306`.

This preserves the networking behavior needed for policy testing without embedding unnecessary database credentials into workload manifests.

The design therefore validates:

~~text
TCP reachability
destination-port restrictions
pod identity
namespace identity
~~

without introducing plaintext database passwords.

---

## Pre-Policy Connectivity Baseline

Before any NetworkPolicy is applied, Kubernetes Pod networking is permissive.

The baseline validates:

~~text
ALLOW - development client -> development web
ALLOW - development client -> production web
ALLOW - development client -> development database
ALLOW - development client -> production database
ALLOW - production client -> production web
ALLOW - production client -> development web
ALLOW - development web -> development database
ALLOW - development web -> production database
~~

This establishes a known baseline before traffic restrictions are introduced.

---

## Default-Deny Ingress

Both application namespaces use default-deny ingress.

~~yaml
spec:
  podSelector: {}
  policyTypes:
  - Ingress
~~

An empty `podSelector` selects every Pod in the namespace.

Once the policy is active, ingress is denied unless another NetworkPolicy explicitly allows a specific path.

The implementation validates that previously successful connections become blocked after default-deny enforcement.

---

## Development Client-to-Web Access

A selective policy allows:

~~text
development/test-client
        |
        | TCP/80
        v
development/web-app
~~

The source identity is selected with:

~~yaml
app: client
tier: testing
~~

The destination is selected using:

~~yaml
app: web
tier: frontend
~~

This rule does not grant direct database access.

---

## Development Web-to-Database Access

The backend tier permits database traffic only from the frontend web workload.

~~text
development/web-app
        |
        | TCP/3306
        v
development/database
~~

The database selector is:

~~yaml
app: db
tier: backend
~~

The allowed source selector is:

~~yaml
app: web
tier: frontend
~~

The development test client remains blocked from direct database access.

---

## Controlled Cross-Namespace Access

One tightly scoped production path is permitted:

~~text
development/web-app
        |
        | TCP/3306
        v
production/database
~~

The cross-namespace peer combines both namespace and workload identity.

~~yaml
from:
- namespaceSelector:
    matchLabels:
      environment: dev
  podSelector:
    matchLabels:
      app: web
      tier: frontend
~~

Both conditions must match.

This prevents:

- development test clients from reaching the production database
- development workloads from reaching the production web tier
- unauthorized production-side workload access

---

## NetworkPolicy Selector Semantics

Peer structure is significant.

Separate entries under `from` or `to` behave as OR conditions.

For example:

~~yaml
from:
- namespaceSelector:
    matchLabels:
      environment: dev
- podSelector:
    matchLabels:
      app: web
~~

can match either peer condition.

By contrast:

~~yaml
from:
- namespaceSelector:
    matchLabels:
      environment: dev
  podSelector:
    matchLabels:
      app: web
      tier: frontend
~~

requires both namespace and Pod identity to match.

The implementation uses this second pattern where cross-namespace least privilege is required.

---

## Development Web Egress Control

The development web workload is also egress isolated.

Permitted outbound paths are:

~~text
development/database TCP/3306
production/database TCP/3306
CoreDNS UDP/53
CoreDNS TCP/53
~~

Denied paths include:

~~text
development web -> production web TCP/80
development web -> Kubernetes API TCP/443
development web -> unrestricted external HTTP
~~

This limits lateral and outbound movement from the frontend workload.

---

## Explicit DNS Egress

Once egress isolation is enabled, DNS must be deliberately allowed.

CoreDNS is selected through:

~~yaml
namespaceSelector:
  matchLabels:
    kubernetes.io/metadata.name: kube-system

podSelector:
  matchLabels:
    k8s-app: kube-dns
~~

Only:

~~text
TCP/53
UDP/53
~~

are permitted.

This avoids using an unrestricted DNS destination.

---

## Advanced Label-Based Selection

Additional workload labels demonstrate more granular identity controls.

~~text
web-app:
  access-level=standard

database:
  access-level=restricted

test-client:
  access-level=testing
~~

The restricted backend is selected using:

~~yaml
access-level: restricted
~~

Allowed frontend sources additionally match:

~~yaml
access-level: standard
~~

and:

~~yaml
matchExpressions:
- key: tier
  operator: In
  values:
  - frontend
~~

This demonstrates policy decisions based on multiple workload attributes.

---

## Final Connectivity Matrix

### Allowed

~~text
development/test-client
    -> development/web-app:80

development/web-app
    -> development/database:3306

development/web-app
    -> production/database:3306

development/web-app
    -> CoreDNS:53 TCP/UDP
~~

### Denied

~~text
development/test-client
    -> development/database:3306

development/test-client
    -> production/database:3306

development/test-client
    -> production/web-app:80

development/web-app
    -> production/web-app:80

development/web-app
    -> Kubernetes API:443

production/test-client
    -> production/web-app:80

production/test-client
    -> production/database:3306

production/test-client
    -> development/web-app:80
~~

---

## Automated Policy Validation

The reusable test suite is:

~~text
scripts/test-network-policies.sh
~~

It systematically validates both expected ALLOW and expected DENY paths.

Each test includes:

~~text
source workload
source namespace
destination
destination port
expected result
actual result
PASS/FAIL status
~~

The script returns a non-zero exit code whenever policy behavior differs from the intended connectivity model.

This makes regression testing possible after future policy changes.

---

## Troubleshooting Workflow

### Verify Cluster Health

~~bash
kubectl get nodes
kubectl get pods -A
~~

### Verify Calico

~~bash
kubectl get tigerastatus
~~

### Inventory Policies

~~bash
kubectl get networkpolicy -A
~~

### Inspect a Policy

~~bash
kubectl describe networkpolicy <policy-name> -n <namespace>
~~

### Verify Pod Labels

~~bash
kubectl get pods -n <namespace> --show-labels
~~

### Verify Namespace Labels

~~bash
kubectl get namespaces --show-labels
~~

### Test DNS

~~bash
kubectl exec -n development test-client -- \
  nslookup kubernetes.default.svc.cluster.local
~~

---

## Immutable Pod Configuration

During validation, the long-running client command required adjustment.

A running Pod's container command is immutable.

The correct replacement workflow is:

~~text
Validate replacement manifest
        |
        v
Delete existing Pod
        |
        v
Create replacement Pod
        |
        v
Wait for Ready
        |
        v
Resume validation
~~

This behavior is documented in the troubleshooting runbook.

---

## Policy Export

Active configuration is exported for later inspection.

~~text
exports/
├── development/
│   ├── namespace.yaml
│   └── networkpolicies.yaml
└── production/
    ├── namespace.yaml
    └── networkpolicies.yaml
~~

Runtime-heavy Pod exports are intentionally excluded from the repository package.

---

## Security Model

The final model follows:

~~text
Default Deny
     |
     v
Explicit Workload Identity
     |
     v
Narrow Port Access
     |
     v
Controlled Namespace Boundaries
     |
     v
Restricted Egress
     |
     v
Automated Validation
~~

The core principle is:

**Deny by default and explicitly permit only required communication paths.**

---

## Repository Structure

~~text
kubernetes-network-policy-isolation/
├── README.md
├── manifests/
│   ├── development-namespace.yaml
│   ├── production-namespace.yaml
│   ├── dev-web-pod.yaml
│   ├── dev-db-pod.yaml
│   ├── dev-test-client.yaml
│   ├── prod-web-pod.yaml
│   ├── prod-db-pod.yaml
│   ├── prod-test-client.yaml
│   ├── dev-default-deny-ingress.yaml
│   ├── prod-default-deny-ingress.yaml
│   ├── dev-allow-client-to-web.yaml
│   ├── dev-allow-web-to-db.yaml
│   ├── prod-allow-dev-web-to-db.yaml
│   ├── dev-web-egress.yaml
│   └── dev-advanced-access.yaml
├── scripts/
│   └── test-network-policies.sh
├── exports/
│   ├── development/
│   │   ├── namespace.yaml
│   │   └── networkpolicies.yaml
│   └── production/
│       ├── namespace.yaml
│       └── networkpolicies.yaml
└── evidence/
    ├── network-policy-environment.txt
    ├── namespace-isolation-baseline.txt
    ├── workload-baseline.txt
    ├── pre-policy-connectivity.txt
    ├── default-deny-validation.txt
    ├── selective-development-policy-validation.txt
    ├── cross-namespace-policy-validation.txt
    ├── development-web-egress-validation.txt
    ├── network-policy-test-suite.txt
    ├── development-policy-analysis.txt
    ├── production-policy-analysis.txt
    ├── final-connectivity-matrix.txt
    ├── final-network-policy-inventory.txt
    ├── development-client-dns-test.txt
    ├── final-network-policy-test-run.txt
    ├── final-policy-inventory.txt
    ├── final-pod-label-inventory.txt
    ├── network-policy-security-model.txt
    ├── network-policy-troubleshooting-runbook.txt
    └── final-network-isolation-summary.txt
~~

Only artifacts that exist locally are copied during packaging.

---

## Skills Demonstrated

- Kubernetes administration
- kubeadm
- containerd
- Calico
- Kubernetes networking
- NetworkPolicy
- namespace segmentation
- default-deny security
- podSelector
- namespaceSelector
- matchLabels
- matchExpressions
- ingress controls
- egress controls
- DNS policy design
- cross-namespace access control
- workload identity
- TCP port restrictions
- network troubleshooting
- connectivity testing
- automated policy validation
- security documentation
- configuration export

---

## Operational Relevance

These techniques apply to:

- platform engineering
- DevOps
- SRE
- Kubernetes administration
- cloud-native security
- production workload segmentation
- east-west traffic control
- zero-trust infrastructure
- compliance-driven network separation
- lateral-movement reduction
- incident containment

The central workflow demonstrated is:

~~text
Permissive Kubernetes Network
          |
          v
Namespace Segmentation
          |
          v
Default Deny
          |
          v
Explicit Ingress Exceptions
          |
          v
Controlled Cross-Namespace Access
          |
          v
Restricted Egress
          |
          v
Automated ALLOW/DENY Testing
          |
          v
Validated Least-Privilege Network Model
~~

The key outcome is not merely creating NetworkPolicy objects, but proving through repeatable testing that required traffic succeeds while unauthorized paths remain blocked.
