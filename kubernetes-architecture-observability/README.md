# Kubernetes Architecture and Observability

This implementation explores Kubernetes cluster architecture by inspecting control-plane components, workload lifecycle behavior, component logs, resource metrics, RBAC objects, and API health endpoints.

The environment uses a single-node Minikube cluster to make the internal interaction between Kubernetes components directly observable.

## Architecture

```text
                         ┌──────────────────┐
                         │     kubectl      │
                         └────────┬─────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │    API Server    │
                         └───────┬──────────┘
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
                ▼                ▼                ▼
             etcd           Scheduler      Controller Manager
                                 │
                                 ▼
                              Kubelet
                                 │
                                 ▼
                        Container Runtime
                                 │
                                 ▼
                                Pod
```

## What Was Implemented

### Control Plane Inspection

The cluster control plane was inspected through the `kube-system` namespace.

Observed components included:

- kube-apiserver
- etcd
- kube-scheduler
- kube-controller-manager

Each component was inspected for:

- runtime status
- node placement
- Pod details
- recent logs
- health indicators

## API Server Analysis

The API Server was inspected as the central communication interface of the cluster.

The analysis included:

- Pod discovery
- detailed component inspection
- log review
- readiness checks
- liveness checks
- general health checks

Health endpoints included:

```text
/readyz
/livez
/healthz
```

These checks confirmed that the API Server and its dependencies were operating correctly.

## etcd Analysis

etcd was examined as the persistent data store for Kubernetes cluster state.

The work included:

- identifying the etcd Pod
- inspecting its configuration
- reviewing recent logs
- checking health-related messages
- checking for latency or slow-operation indicators

etcd stores the state that Kubernetes controllers and API operations depend on.

## Scheduler Analysis

Scheduler logs were inspected to understand workload placement behavior.

The scheduler is responsible for selecting an appropriate node for Pods that do not yet have a node assignment.

Scheduling decisions can consider:

- CPU requests
- memory requests
- node availability
- affinity rules
- taints and tolerations
- scheduling constraints

## Controller Manager Analysis

Controller Manager logs were inspected to understand reconciliation behavior.

Controllers continuously compare desired state with actual state and take action when differences occur.

Examples include:

- replica reconciliation
- endpoint management
- service account management
- node lifecycle management
- workload lifecycle management

## Pod Lifecycle Analysis

A standalone nginx Pod was created and observed throughout its lifecycle.

The workflow traced interactions across:

```text
kubectl
   |
   v
API Server
   |
   +----------------------+
   |                      |
   v                      v
etcd                 Scheduler
                           |
                           v
                      Node selected
                           |
                           v
                         Kubelet
                           |
                           v
                   Container Runtime
                           |
                           v
                       nginx Pod
```

The Pod lifecycle was inspected using:

- Pod status
- Pod description
- Kubernetes events
- scheduler logs
- API Server logs
- kubelet logs
- container runtime identifiers
- Pod IP information

## Kubelet Interaction

Kubelet behavior was inspected from inside the Minikube node.

The kubelet is responsible for ensuring that Pods assigned to its node are running as declared.

It communicates with the container runtime to manage:

- container creation
- image retrieval
- container startup
- container termination
- runtime status reporting

## Container Runtime Visibility

The runtime container identifier for the nginx workload was extracted from Pod status.

This demonstrated the relationship between the Kubernetes Pod abstraction and the actual runtime container underneath it.

## Pod Networking

The Pod received its own cluster IP address.

Connectivity was tested using:

- direct Pod IP access from the Minikube node
- Pod-to-Pod communication
- temporary port forwarding

This demonstrated that Pod networking exists independently from host-level container port mappings.

## Port Forwarding

A local port-forward was established between the host and the nginx Pod.

```text
localhost:8080
        |
        v
 Kubernetes API
        |
        v
   nginx-demo:80
```

This allowed temporary local access without creating a persistent Kubernetes Service.

## Cluster Events

Kubernetes events were inspected to understand the workload creation sequence.

Events provide visibility into operations such as:

- scheduling
- image pulling
- container creation
- container startup
- readiness
- failures

These are important during workload troubleshooting.

## Resource Metrics

Metrics Server was enabled to expose resource consumption information.

The following commands were used:

```text
kubectl top nodes
kubectl top pods
```

This provided CPU and memory usage information at both node and workload level.

## Resource Allocation

Node resource allocation was inspected to compare requested and limited resources.

This helps evaluate:

- scheduling pressure
- available capacity
- CPU reservation
- memory reservation
- resource overcommitment

## Service Accounts

Service accounts in the `kube-system` namespace were inspected.

Service accounts provide identities for Kubernetes workloads and system components.

These identities can then be granted permissions through RBAC.

## Kubernetes RBAC

Cluster-wide authorization objects were inspected.

The analysis included:

- ClusterRoles
- ClusterRoleBindings
- system roles
- controller permissions
- cluster-admin permissions

The authorization model can be summarized as:

```text
Identity
   |
   v
ServiceAccount / User / Group
   |
   v
RoleBinding / ClusterRoleBinding
   |
   v
Role / ClusterRole
   |
   v
Allowed API Operations
```

## Component Health

Multiple methods were used to evaluate cluster health.

These included:

- control-plane Pod status
- API readiness
- API liveness
- API health
- component status
- cluster node readiness
- component logs

The observed control-plane components reported healthy status during validation.

## Kubernetes Component Responsibilities

| Component | Primary Responsibility |
|---|---|
| API Server | Central Kubernetes API and cluster communication |
| etcd | Persistent cluster state |
| Scheduler | Assigns Pods to nodes |
| Controller Manager | Runs reconciliation controllers |
| Kubelet | Manages Pods assigned to a node |
| Container Runtime | Executes containers |
| Metrics Server | Provides resource usage metrics |
| CoreDNS | Provides cluster DNS |
| kube-proxy | Implements Service networking behavior |

## Repository Contents

```text
kubernetes-architecture-observability/
├── README.md
├── architecture-analysis.md
├── component-flow.md
├── apiserver-logs.txt
├── etcd-logs.txt
├── scheduler-logs.txt
├── controller-manager-logs.txt
├── node-metrics.txt
├── pod-metrics.txt
├── kube-system-serviceaccounts.txt
├── clusterroles.txt
├── clusterrolebindings.txt
├── control-plane-state.txt
├── pod-events.txt
└── pod-state.txt
```

## Operational Troubleshooting Model

Understanding Kubernetes architecture makes troubleshooting more systematic.

### Pod Not Scheduled

Inspect:

```text
Pod events
Scheduler logs
Node resources
Resource requests
Taints and tolerations
```

### Pod Not Starting

Inspect:

```text
Pod description
Kubelet logs
Container runtime state
Image pull events
Container status
```

### API Problems

Inspect:

```text
API Server logs
/readyz
/livez
/healthz
Control-plane Pod status
```

### Cluster State Problems

Inspect:

```text
etcd health
etcd logs
API Server connectivity
Control-plane status
```

### Authorization Problems

Inspect:

```text
ServiceAccounts
ClusterRoles
ClusterRoleBindings
RBAC permissions
```

## Key Engineering Lessons

### The API Server Is the Coordination Hub

Cluster components primarily coordinate through the Kubernetes API.

This avoids direct coupling between individual components.

### etcd Is the Source of Persistent Cluster State

Kubernetes relies on etcd for durable storage of cluster objects and desired state.

### Controllers Reconcile Continuously

Controllers do not simply execute a one-time command.

They continuously compare actual state against desired state and take corrective action.

### Scheduler and Kubelet Have Different Responsibilities

The scheduler determines where a workload should run.

The kubelet ensures that the workload actually runs on the selected node.

### Observability Requires Multiple Data Sources

Troubleshooting Kubernetes effectively requires combining:

- resource state
- events
- logs
- health endpoints
- metrics
- runtime information

No single command provides the complete picture.

## Key Takeaway

Kubernetes is an API-driven distributed control system.

The API Server provides the central interface, etcd persists cluster state, the scheduler places workloads, controllers reconcile desired state, kubelets manage node-level execution, and the container runtime runs the actual containers.

Understanding these interactions provides the foundation for deeper Kubernetes administration, troubleshooting, performance analysis, and security engineering.
