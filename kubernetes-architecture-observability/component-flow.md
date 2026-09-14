# Kubernetes Pod Lifecycle and Component Flow

## Request Submission

The Pod manifest is submitted through `kubectl` to the Kubernetes API Server.

The API Server validates and stores the requested object state.

## Scheduling

The scheduler detects an unscheduled Pod and selects an appropriate node based on available resources and scheduling constraints.

The selected node is written back to the Pod specification through the API Server.

## Node Execution

The kubelet running on the selected node observes the assigned Pod.

The kubelet communicates with the container runtime to:

- obtain the required container image
- create the container
- configure the Pod sandbox
- start the workload
- monitor container health and state

## Runtime State

The container runtime creates the nginx container and reports its runtime identifier and status through the kubelet.

The kubelet updates Pod status through the API Server.

## Networking

The Pod receives its own cluster network address.

The application can be reached from other cluster workloads using the Pod IP while the Pod remains active.

Port forwarding can also create a temporary local connection through the Kubernetes API to the Pod.

## State Observation

Pod state can be inspected through:

- `kubectl get`
- `kubectl describe`
- Kubernetes events
- scheduler logs
- API Server logs
- kubelet logs
- container runtime identifiers

## Communication Flow

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

The API Server acts as the central communication interface for cluster state changes.

Controllers, schedulers, kubelets, and clients interact with cluster state through the Kubernetes API rather than directly coordinating application state with each other.
