# Kubernetes Resource Governance

## Overview

This implementation demonstrates Kubernetes resource governance using CPU and memory requests, resource limits, namespace ResourceQuotas, LimitRanges, quota-aware workload scaling, resource monitoring, and structured troubleshooting.

The workflow covers:

- node capacity inspection
- allocatable resource inspection
- live Kubernetes metrics
- CPU requests
- CPU limits
- memory requests
- memory limits
- QoS classification
- namespace ResourceQuota
- quota admission enforcement
- Deployment resource accounting
- quota-aware horizontal scaling
- ReplicaSet FailedCreate diagnostics
- LimitRange defaults
- automatic resource injection
- resource troubleshooting
- corrected workload deployment
- final evidence capture
- namespace cleanup

## Architecture

```text
                        Kubernetes Cluster
                               |
                               v
                         +------------+
                         |    Node    |
                         +------------+
                         | Capacity   |
                         | Allocatable|
                         +-----+------+
                               |
                               v
                +-----------------------------+
                | Namespace: resource-governance |
                +-----------------------------+
                     |                   |
                     |                   |
                     v                   v
              +--------------+    +-------------+
              | ResourceQuota|    | LimitRange  |
              +--------------+    +-------------+
              | Namespace    |    | Container   |
              | budget       |    | defaults    |
              +------+-------+    +------+------+
                     |                   |
                     +---------+---------+
                               |
                               v
                    +---------------------+
                    | Workloads / Pods    |
                    +---------------------+
                    | requests.cpu        |
                    | requests.memory     |
                    | limits.cpu          |
                    | limits.memory       |
                    +---------------------+
```

## Repository Structure

```text
kubernetes-resource-governance/
├── README.md
├── pod-with-resources.yaml
├── resource-quota.yaml
├── web-deployment.yaml
├── limit-range.yaml
├── pod-no-resources.yaml
├── problematic-pod.yaml
├── fixed-pod.yaml
├── resource-model.md
├── resource-quota-model.md
├── quota-aware-scaling.md
├── limitrange-model.md
├── resource-troubleshooting.md
└── evidence/
```

## Environment

Validated with:

- Ubuntu Linux
- Docker
- Kubernetes via Minikube
- containerd
- kubectl
- Metrics Server
- jq
- curl

## Namespace

Runtime resources were isolated inside:

```text
resource-governance
```

This keeps quota and policy behavior scoped to a dedicated namespace.

## Kubernetes Resource Model

Kubernetes distinguishes between resource requests and resource limits.

### Requests

Requests influence scheduler placement and quota accounting.

Example:

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "64Mi"
```

`250m` represents 250 millicores, or 0.25 CPU.

### Limits

Limits define runtime ceilings.

Example:

```yaml
resources:
  limits:
    cpu: "500m"
    memory: "128Mi"
```

CPU usage above a configured limit may be throttled.

Memory usage above an enforced memory limit can result in container termination.

## Resource-Constrained Pod

A workload was deployed with:

```text
CPU request:     250m
CPU limit:       500m
Memory request:  64Mi
Memory limit:    128Mi
```

The resource specification was validated directly through the Kubernetes API.

## QoS Classification

Because the Pod had resource requests lower than its corresponding limits, Kubernetes classified it as:

```text
Burstable
```

QoS classification affects workload treatment during node resource pressure.

## Node Capacity

Node capacity and allocatable resources were inspected using Kubernetes APIs.

Important distinction:

```text
Capacity
    = total node resources

Allocatable
    = resources Kubernetes can allocate to Pods
```

Allocatable resources are typically lower than total node capacity because some resources are reserved for the operating system and Kubernetes components.

## Live Resource Metrics

Metrics Server was enabled and queried using:

```bash
kubectl top nodes
kubectl top pods
```

This provided runtime CPU and memory usage alongside declared resource requests and limits.

## ResourceQuota

A namespace-level ResourceQuota was configured with:

```yaml
hard:
  requests.cpu: "1"
  requests.memory: 1Gi
  limits.cpu: "2"
  limits.memory: 2Gi
  persistentvolumeclaims: "4"
  pods: "10"
  services: "5"
```

This defines an aggregate namespace resource budget.

## Quota Scope

ResourceQuota can govern:

- total CPU requests
- total memory requests
- total CPU limits
- total memory limits
- Pod count
- Service count
- PersistentVolumeClaim count

This is especially useful in shared and multi-tenant Kubernetes environments.

## Admission-Time Quota Enforcement

An intentionally oversized Pod requested:

```text
CPU request:     1500m
Memory request:  2Gi
CPU limit:       2500m
Memory limit:    3Gi
```

These values exceeded the namespace quota.

The workload was rejected during admission.

Conceptually:

```text
Pod submitted
    |
    v
API Server
    |
    v
Admission Control
    |
    v
ResourceQuota Evaluation
    |
    +--> within budget -> Pod admitted
    |
    +--> quota exceeded -> request rejected
```

A quota-rejected Pod is different from a Pending Pod.

The object may never be created.

## ResourceQuota Evidence

Used and hard values were captured for:

```text
requests.cpu
requests.memory
limits.cpu
limits.memory
pods
```

This demonstrates that quota decisions are based on aggregate namespace consumption rather than isolated workload configuration.

## Resource-Constrained Deployment

A three-replica web Deployment was configured with each replica requesting:

```text
CPU request:     100m
Memory request:  32Mi
CPU limit:       200m
Memory limit:    64Mi
```

For three replicas, the Deployment contributes:

```text
CPU requests:     300m
Memory requests:  96Mi
CPU limits:       600m
Memory limits:    192Mi
```

## Quota-Aware Scaling

The Deployment was intentionally scaled from:

```text
3 replicas
```

to:

```text
8 replicas
```

The Deployment controller accepted the desired replica count, but individual Pod creation remained subject to namespace ResourceQuota admission.

Architecture:

```text
Deployment
    |
    v
ReplicaSet
    |
    v
Create Pod
    |
    v
Admission Control
    |
    +--> quota available
    |        |
    |        v
    |     Pod created
    |
    +--> quota exceeded
             |
             v
        FailedCreate
```

## Desired Replicas vs Admitted Pods

An important operational lesson is that:

```text
Deployment desired replicas
```

does not necessarily equal:

```text
successfully admitted Pods
```

A controller can desire more replicas than namespace policy permits.

The ReplicaSet surfaces this through failure conditions and events.

## ResourceQuota Failure vs Scheduler Failure

These are different failure modes.

### ResourceQuota Failure

Occurs during admission.

Typical evidence:

```text
Forbidden
exceeded quota
FailedCreate
```

The Pod may not exist.

### Scheduler Resource Failure

Occurs after admission.

Typical evidence:

```text
Pending
FailedScheduling
Insufficient cpu
Insufficient memory
```

The Pod exists but cannot be assigned to a node.

This distinction significantly reduces troubleshooting time.

## LimitRange

A namespace LimitRange was configured with:

```yaml
defaultRequest:
  cpu: "100m"
  memory: "64Mi"

default:
  cpu: "200m"
  memory: "128Mi"
```

## Automatic Resource Injection

A Pod was submitted without any explicit resource section.

Original workload:

```yaml
containers:
  - name: default-container
    image: busybox:1.37
```

After admission, Kubernetes populated resource values using the LimitRange.

The resulting Pod received:

```text
CPU request:     100m
Memory request:  64Mi
CPU limit:       200m
Memory limit:    128Mi
```

## Admission Flow with LimitRange and ResourceQuota

Conceptually:

```text
Pod submitted
    |
    v
LimitRange processing
    |
    v
Missing defaults injected
    |
    v
ResourceQuota evaluated
    |
    v
Pod admitted or rejected
```

This combination creates predictable resource governance.

## LimitRange vs ResourceQuota

### LimitRange

Controls defaults and boundaries for individual workload resource declarations.

### ResourceQuota

Controls aggregate namespace consumption.

Together:

```text
LimitRange
    +
ResourceQuota
    =
consistent per-workload sizing
    +
namespace-level resource budget
```

## Problematic Workload

A deliberately oversized workload was used to test troubleshooting:

```text
CPU request:     800m
Memory request:  1Gi
CPU limit:       1200m
Memory limit:    1536Mi
```

Its creation was evaluated against the namespace's remaining quota.

The resulting API output and events were captured as troubleshooting evidence.

## Corrected Workload

The workload was corrected to:

```text
CPU request:     50m
Memory request:  32Mi
CPU limit:       100m
Memory limit:    64Mi
```

The corrected Pod was successfully admitted and became Ready.

This demonstrates remediation through right-sizing rather than bypassing namespace policy.

## Resource Monitoring

Operational resource inspection included:

```bash
kubectl top pods -n resource-governance
```

and structured resource views containing:

```text
Pod name
CPU request
CPU limit
Memory request
Memory limit
QoS class
```

## Troubleshooting Workflow

A useful sequence is:

```text
kubectl get pods
        |
        v
kubectl describe pod
        |
        v
kubectl get events
        |
        v
kubectl describe resourcequota
        |
        v
kubectl describe limitrange
        |
        v
inspect node allocatable resources
        |
        v
adjust requests / limits / replicas
```

## Capacity Planning Considerations

Resource requests that are too high can:

- reduce scheduling flexibility
- waste namespace quota
- reduce cluster utilization
- prevent additional replicas from being admitted

Requests that are too low can:

- create unrealistic scheduler expectations
- contribute to resource contention
- reduce workload predictability

Limits that are too low can:

- throttle CPU-heavy workloads
- trigger memory termination

Limits that are excessively high can:

- reduce the effectiveness of namespace governance
- allow larger resource bursts than intended

## Multi-Tenant Resource Governance

ResourceQuota and LimitRange are useful for shared clusters where multiple teams or workloads coexist.

A typical pattern is:

```text
Cluster
  |
  +-- Namespace A
  |      |
  |      +-- ResourceQuota
  |      +-- LimitRange
  |
  +-- Namespace B
  |      |
  |      +-- ResourceQuota
  |      +-- LimitRange
  |
  +-- Namespace C
         |
         +-- ResourceQuota
         +-- LimitRange
```

Each namespace receives a controlled resource budget.

## Evidence Capture

Operational evidence was stored under:

```text
evidence/
```

Evidence includes:

- node capacity
- allocatable resources
- live node metrics
- live Pod metrics
- resource specifications
- QoS classifications
- ResourceQuota used vs hard state
- quota rejection output
- Deployment scaling state
- ReplicaSet conditions
- quota-related events
- LimitRange configuration
- automatically injected resources
- corrected workload state
- final node allocation
- final namespace resource inventory

## Cleanup

The runtime namespace was removed after evidence collection:

```bash
kubectl delete namespace resource-governance
```

Local manifests and evidence remain available for review.

## Skills Demonstrated

- Kubernetes CPU requests
- Kubernetes memory requests
- CPU limits
- memory limits
- node capacity inspection
- allocatable resource inspection
- Metrics Server
- kubectl top
- QoS classes
- ResourceQuota
- quota admission control
- namespace resource accounting
- Deployment resource sizing
- quota-aware scaling
- ReplicaSet diagnostics
- FailedCreate analysis
- LimitRange
- automatic default injection
- troubleshooting resource failures
- workload right-sizing
- multi-tenant resource governance

## Real-World Use Cases

These patterns are useful for:

- multi-tenant Kubernetes clusters
- internal developer platforms
- AI inference workloads
- batch processing
- API services
- microservices
- staging environments
- shared engineering clusters
- cost-controlled namespaces
- platform engineering environments

## Key Lessons

- Resource requests influence scheduling and accounting.
- Resource limits define runtime ceilings.
- ResourceQuota governs aggregate namespace consumption.
- Quota violations are rejected during admission.
- Scheduler failures and quota failures are fundamentally different.
- Deployment desired replicas can exceed the number of Pods actually admitted.
- LimitRange can supply missing resource declarations automatically.
- LimitRange and ResourceQuota complement each other.
- Resource metrics should be interpreted alongside declared requests and limits.
- Right-sizing workloads is often the correct remediation for quota failures.
- Namespace-level governance improves cluster stability and resource predictability.
