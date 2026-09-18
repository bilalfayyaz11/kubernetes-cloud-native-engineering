# Kubernetes Network Segmentation

## Overview

This implementation demonstrates Kubernetes network segmentation using NetworkPolicy enforcement with Calico.

It covers:

- open pod networking baseline
- application-tier isolation
- backend ingress protection
- selective Pod access
- namespace-based access controls
- live policy modification
- additive NetworkPolicy behavior
- egress restrictions
- DNS-safe egress rules
- cross-namespace isolation
- connectivity testing
- NetworkPolicy troubleshooting
- evidence capture
- secure runtime credential handling

## Architecture

```text
                 +------------------+
                 | Frontend         |
                 | app=frontend     |
                 +--------+---------+
                          |
                          | TCP/5432 ALLOW
                          v
                 +------------------+
                 | Backend Database |
                 | app=backend      |
                 +------------------+
                      ^        |
                      X        | TCP/80 ALLOW
                      |        v
              +-------+---+  Frontend
              | Test Client|
              +-----------+

External Namespace
----------------------------

+------------------+
| External Client  |
+--------+---------+
         |
         X TCP/5432

Backend Egress:

backend
  |
  +--> frontend:80
  |
  +--> CoreDNS:53
  |
  X--> external-web:80
```

## Repository Structure

```text
kubernetes-network-segmentation/
├── README.md
├── .gitignore
├── frontend-pod.yaml
├── backend-pod.yaml
├── test-client-pod.yaml
├── external-client-pod.yaml
├── backend-service.yaml
├── deny-backend-ingress.yaml
├── allow-frontend-to-backend.yaml
├── allow-frontend-and-testclient.yaml
├── allow-trusted-namespace-to-backend.yaml
├── backend-egress-policy.yaml
├── frontend-service.yaml
├── external-web.yaml
├── open-network-baseline.md
├── networkpolicy-ingress-model.md
├── networkpolicy-troubleshooting.md
├── network-segmentation-model.md
├── test-network-segmentation.sh
└── evidence/
```

## Environment

Validated using:

- Ubuntu Linux
- Docker
- Minikube
- containerd
- kubectl
- Calico CNI
- Kubernetes NetworkPolicy API
- PostgreSQL
- Nginx
- BusyBox
- jq
- OpenSSL
- netcat

## NetworkPolicy Enforcement

Kubernetes accepts NetworkPolicy objects through its API, but actual packet filtering depends on the cluster network plugin.

This environment uses:

```text
Calico
```

which enforces NetworkPolicy rules.

## Namespaces

Two namespaces are used:

```text
network-segmentation
external-segmentation
```

The application namespace is labeled:

```text
access-zone=trusted
```

The external namespace is labeled:

```text
access-zone=untrusted
```

These labels support namespace-based policy decisions.

## Workloads

The environment contains:

```text
frontend
backend
test-client
external-client
external-web
```

The backend runs PostgreSQL on:

```text
TCP/5432
```

The frontend runs Nginx on:

```text
TCP/80
```

## Runtime Credential Handling

PostgreSQL credentials were generated at runtime.

The password was:

- generated locally
- written only to a temporary file
- loaded into a Kubernetes Secret
- removed after Secret creation
- never stored in committed YAML

The backend manifest references:

```yaml
envFrom:
  - secretRef:
      name: backend-db-credentials
```

## Open Network Baseline

Before NetworkPolicy was applied, communication was tested from:

```text
frontend
test-client
external-client
```

to:

```text
backend:5432
```

Connectivity was validated using:

- direct Pod IP
- ClusterIP Service
- Kubernetes DNS

## Backend Service

The backend is exposed internally using:

```text
backend-db
```

with:

```text
port: 5432
targetPort: 5432
```

The Service selects:

```yaml
app: backend
```

## EndpointSlice

EndpointSlice was used to confirm that the backend Service resolved to the expected Pod.

Conceptually:

```text
Client
  |
  v
backend-db Service
  |
  v
EndpointSlice
  |
  v
backend Pod
```

## Default-Deny Backend Ingress

The backend was isolated using:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-backend-ingress
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
```

Because no ingress rules are defined, selected backend Pods become isolated from incoming traffic.

## Default-Deny Result

After policy enforcement:

```text
frontend       X--> backend
test-client    X--> backend
external-client X--> backend
```

The backend itself remained healthy.

This proves that NetworkPolicy can restrict network access without terminating or disabling the application.

## Selective Frontend Access

A second policy allows:

```text
app=frontend
    |
    | TCP/5432
    v
app=backend
```

The allowed source is selected using:

```yaml
podSelector:
  matchLabels:
    app: frontend
```

The allowed port is:

```text
TCP/5432
```

## Result

After applying the selective allow rule:

```text
frontend       --> backend   ALLOWED
test-client    X-> backend   BLOCKED
external       X-> backend   BLOCKED
```

## Additive NetworkPolicy Behavior

Kubernetes NetworkPolicies are additive.

They are not processed like ordered firewall rules.

If multiple policies select the same Pod, allowed traffic is the union of all applicable allow rules.

Conceptually:

```text
default deny
    +
frontend allow
    =
frontend permitted
all unrelated traffic denied
```

## Pod Selector Scope

A peer such as:

```yaml
from:
  - podSelector:
      matchLabels:
        app: frontend
```

selects Pods from the same namespace as the NetworkPolicy.

## Namespace-Based Access

A namespace-based policy was also tested using:

```yaml
namespaceSelector:
  matchLabels:
    access-zone: trusted
```

This demonstrated that access can be controlled using namespace identity rather than only Pod identity.

## Namespace Result

The trusted application namespace was permitted.

The namespace labeled:

```text
access-zone=untrusted
```

remained blocked.

## Live Policy Modification

NetworkPolicy behavior was changed while workloads remained running.

A temporary policy allowed both:

```text
frontend
test-client
```

to reach the backend.

The test-client immediately became permitted.

After the temporary policy was removed, the test-client became blocked again.

This demonstrates dynamic policy reconciliation.

## Live Change Flow

```text
Initial:
frontend     --> backend
test-client  X-> backend

Temporary policy:
frontend     --> backend
test-client  --> backend

Policy removed:
frontend     --> backend
test-client  X-> backend
```

## Egress Isolation

The backend was then isolated for outgoing connections using:

```yaml
policyTypes:
  - Egress
```

Only explicitly required destinations remained permitted.

## Allowed Backend Egress

The backend can reach:

```text
frontend:80
CoreDNS:53 UDP
CoreDNS:53 TCP
```

## Blocked Backend Egress

The backend cannot reach the external namespace web application:

```text
external-web.external-segmentation.svc.cluster.local:80
```

## DNS-Safe Egress Policy

Restrictive egress rules can accidentally break DNS.

This implementation explicitly allows CoreDNS:

```yaml
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
  ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

This preserves Kubernetes Service discovery while keeping other egress restricted.

## Final Ingress Model

```text
frontend
   |
   | TCP/5432
   v
backend

test-client
   |
   X TCP/5432

external-client
   |
   X TCP/5432
```

## Final Egress Model

```text
backend
   |
   +--> frontend:80
   |
   +--> CoreDNS:53
   |
   X--> external-web:80
```

## Microsegmentation

The environment moves from:

```text
any workload
    |
    v
backend
```

to:

```text
approved source
    |
    v
backend
```

This significantly reduces unnecessary east-west communication.

## NetworkPolicy Troubleshooting

A practical troubleshooting sequence is:

```text
Verify Pod health
    |
    v
Inspect Pod labels
    |
    v
Inspect NetworkPolicy podSelector
    |
    v
Inspect peer selectors
    |
    v
Inspect namespace labels
    |
    v
Verify Service
    |
    v
Verify EndpointSlice
    |
    v
Test direct TCP connectivity
    |
    v
Test DNS separately
    |
    v
Inspect CNI components
```

## NetworkPolicy API vs Enforcement

A NetworkPolicy resource existing in the API does not prove that traffic is actually filtered.

Always verify:

```text
CNI supports NetworkPolicy
```

and test real connections.

## Policy Selection

A policy affects only Pods matched by:

```yaml
spec:
  podSelector:
```

Incorrect labels can cause a policy to affect:

- no Pods
- the wrong Pods
- more Pods than intended

## Ingress Isolation

A Pod becomes ingress-isolated when a NetworkPolicy selects it for:

```yaml
policyTypes:
  - Ingress
```

Allowed incoming traffic is then defined by applicable ingress rules.

## Egress Isolation

A Pod becomes egress-isolated when a NetworkPolicy selects it for:

```yaml
policyTypes:
  - Egress
```

Outgoing traffic must then match applicable egress rules.

## DNS Troubleshooting

If an application loses Service discovery after egress isolation:

1. verify CoreDNS Pods
2. inspect CoreDNS labels
3. verify namespace selector
4. permit UDP/53
5. permit TCP/53
6. retest DNS separately from application connectivity

## Violation Events

Standard Kubernetes NetworkPolicy does not guarantee that blocked traffic generates a Kubernetes Event.

Therefore:

```text
no event
```

does not mean:

```text
policy not enforced
```

Connectivity testing is the primary validation method used here.

## Comprehensive Test Script

The repository includes:

```text
test-network-segmentation.sh
```

It validates:

- frontend → backend allowed
- test-client → backend blocked
- external-client → backend blocked
- backend → frontend allowed
- backend → external-web blocked
- backend DNS resolution allowed

## Evidence

Evidence captured includes:

- cluster node state
- Calico system state
- namespace labels
- workload Pod state
- Pod labels
- backend Service
- EndpointSlice state
- DNS resolution
- open-connectivity baseline
- default-deny behavior
- selective allow behavior
- namespace selector behavior
- final NetworkPolicy resources
- egress behavior
- CoreDNS labels
- final connectivity matrix
- Kubernetes events
- comprehensive validation results

## Cleanup

Both runtime namespaces were deleted:

```bash
kubectl delete namespace network-segmentation
kubectl delete namespace external-segmentation
```

Local implementation files and evidence remain available for review.

## Skills Demonstrated

- Kubernetes NetworkPolicy
- Calico
- pod isolation
- ingress controls
- egress controls
- Pod selectors
- namespace selectors
- namespace labels
- additive policy behavior
- microsegmentation
- DNS-aware network policy design
- PostgreSQL connectivity testing
- Service discovery
- EndpointSlice
- cross-namespace isolation
- live policy modification
- connectivity troubleshooting
- network security evidence capture

## Real-World Use Cases

These patterns apply to:

- microservices
- database isolation
- internal APIs
- AI inference services
- multi-tenant clusters
- regulated workloads
- platform engineering
- shared Kubernetes environments
- zero-trust cluster networking
- defense-in-depth architectures

## Key Lessons

- Kubernetes Pods are generally reachable according to the cluster network unless policy enforcement restricts them.
- NetworkPolicy requires a compatible CNI.
- Calico provides NetworkPolicy enforcement in this environment.
- A backend can be isolated without disrupting its process health.
- Pod selectors enable workload-specific access control.
- Namespace selectors enable security-zone boundaries.
- NetworkPolicies are additive.
- Live policy updates can change traffic behavior without restarting workloads.
- Egress isolation must account for DNS.
- CoreDNS access should be explicitly permitted when egress is restricted.
- Kubernetes Events are not a reliable universal source for blocked-packet evidence.
- Real connectivity tests are essential for proving enforcement.
- NetworkPolicy provides a strong foundation for Kubernetes microsegmentation and least-privilege east-west traffic control.
