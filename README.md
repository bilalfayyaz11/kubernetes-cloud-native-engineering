# Kubernetes & Cloud-Native Engineering

Hands-on implementations covering Kubernetes architecture, networking, security, storage, delivery, GitOps, observability, and service mesh patterns.

This repository focuses on practical cluster engineering rather than isolated YAML examples.

## What This Repository Covers

* Kubernetes cluster bootstrap and administration
* containerd-based runtime configuration
* pod, deployment, service, and workload management
* persistent storage and volume lifecycle
* multi-tier application architecture
* ingress and HTTPS routing
* RBAC and namespace-level security
* workload hardening and security controls
* CI/CD delivery into Kubernetes
* Argo CD GitOps reconciliation
* Istio service mesh
* mTLS and workload authorization
* traffic splitting, retries, timeouts, and fault injection
* observability and proxy diagnostics

---

## Implementations

| Area                    | Implementation                                                                     | Focus                                                                |
| ----------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| GitOps                  | [`argocd-gitops-delivery`](./argocd-gitops-delivery)                               | Argo CD, automated sync, self-healing, pruning, Git-based recovery   |
| Service Mesh            | [`istio-service-mesh`](./istio-service-mesh)                                       | Istio, Envoy, mTLS, authorization, traffic management, observability |
| Cluster Bootstrap       | [`kubeadm-containerd-flannel-cluster`](./kubeadm-containerd-flannel-cluster)       | kubeadm, containerd, Flannel, control plane and worker setup         |
| CI/CD                   | [`kubernetes-cicd-delivery`](./kubernetes-cicd-delivery)                           | automated Kubernetes application delivery workflow                   |
| Security Hardening      | [`kubernetes-security-hardening`](./kubernetes-security-hardening)                 | workload security, security contexts, policy-oriented hardening      |
| RBAC                    | [`kubernetes-rbac-security-controls`](./kubernetes-rbac-security-controls)         | roles, bindings, namespace isolation, access control                 |
| Ingress                 | [`kubernetes-ingress-routing`](./kubernetes-ingress-routing)                       | HTTP/HTTPS ingress, TLS, host and path routing                       |
| Multi-Tier Architecture | [`kubernetes-multi-tier-architecture`](./kubernetes-multi-tier-architecture)       | frontend, backend, service discovery, application segmentation       |
| Persistent Storage      | [`kubernetes-persistent-storage`](./kubernetes-persistent-storage)                 | PVs, PVCs, StorageClasses, persistent workload lifecycle             |
| Observability           | [`kubernetes-architecture-observability`](./kubernetes-architecture-observability) | cluster architecture inspection, metrics, events, diagnostics        |
| Workload Management     | [`kubernetes-workload-management`](./kubernetes-workload-management)               | pods, deployments, scaling, rollouts, service exposure               |
| Container Orchestration | [`container-orchestration-foundations`](./container-orchestration-foundations)     | container scheduling, orchestration fundamentals, cluster operations |

---

## Architecture Areas

### Cluster Engineering

Built Kubernetes environments from the infrastructure layer upward using:

* kubeadm
* containerd
* Flannel
* kubectl
* Minikube

The focus is understanding how Kubernetes components interact instead of treating the cluster as a black box.

### Application Delivery

Workloads are deployed through multiple delivery models:

```text
Manual Kubernetes deployment
        |
        v
Declarative manifests
        |
        v
CI/CD pipelines
        |
        v
GitOps reconciliation
```

The GitOps implementation extends this further:

```text
Git
 |
 v
Argo CD
 |
 v
Kubernetes
 |
 v
Continuous reconciliation
```

### Networking

Networking implementations cover:

* ClusterIP services
* service discovery
* multi-tier connectivity
* ingress routing
* HTTPS/TLS
* Flannel CNI
* Envoy-based service communication
* service-mesh traffic management

### Security

Security controls include:

* Kubernetes RBAC
* namespace-level access controls
* workload security contexts
* least-privilege configuration
* strict mTLS
* workload identity
* Istio AuthorizationPolicy
* secure east-west service communication

### Reliability

Resilience patterns implemented across the repository include:

* health checks
* readiness and liveness probes
* rolling deployments
* retries
* request timeouts
* connection pooling
* outlier detection
* fault injection
* GitOps self-healing
* automatic resource pruning

### Observability

Operational visibility includes:

* Kubernetes events
* workload logs
* cluster state inspection
* Prometheus metrics
* Grafana dashboards
* Kiali service topology
* Jaeger tracing
* Envoy cluster, listener, and route inspection

---

## GitOps

The Argo CD implementation demonstrates Git as the source of truth for Kubernetes state.

Key behaviors validated:

```text
Git commit
   ↓
Argo CD detects revision
   ↓
Automated synchronization
   ↓
Kubernetes reconciliation
```

Additional validation includes:

* live-cluster drift correction
* automated pruning
* Git-driven configuration changes
* controlled deployment failure
* troubleshooting through Kubernetes events
* recovery through a Git commit instead of manual cluster repair

See:

[`argocd-gitops-delivery`](./argocd-gitops-delivery)

---

## Service Mesh

The Istio implementation applies service-mesh controls around a multi-service Kubernetes workload.

Implemented capabilities include:

* Envoy sidecar injection
* header-based routing
* weighted traffic splitting
* strict mTLS
* identity-aware authorization
* least-request load balancing
* retries and timeouts
* outlier detection
* connection limits
* controlled fault injection
* Prometheus telemetry
* Kiali topology
* Grafana dashboards
* Jaeger tracing

See:

[`istio-service-mesh`](./istio-service-mesh)

---

## Security Model

```text
External Traffic
      |
      v
Ingress / Gateway
      |
      v
Kubernetes Services
      |
      v
Workloads
      |
      +---- RBAC
      |
      +---- Security Contexts
      |
      +---- Health Controls
      |
      +---- mTLS
      |
      +---- Workload Identity
      |
      +---- Authorization Policies
```

The security implementations span both Kubernetes-native controls and service-mesh-level controls.

---

## Technology Stack

```text
Kubernetes
Docker
containerd
kubeadm
Minikube
Flannel
Argo CD
Istio
Envoy
Prometheus
Grafana
Kiali
Jaeger
Git
GitHub
Linux
YAML
Bash
```

---

## Repository Structure

```text
kubernetes-cloud-native-engineering/
│
├── argocd-gitops-delivery/
├── container-orchestration-foundations/
├── istio-service-mesh/
├── kubeadm-containerd-flannel-cluster/
├── kubernetes-architecture-observability/
├── kubernetes-cicd-delivery/
├── kubernetes-ingress-routing/
├── kubernetes-multi-tier-architecture/
├── kubernetes-persistent-storage/
├── kubernetes-rbac-security-controls/
├── kubernetes-security-hardening/
└── kubernetes-workload-management/
```

Each directory contains its own implementation details, configuration, validation steps, and architecture notes.

---

## Engineering Focus

This repository is built around five core areas:

1. **Cluster engineering** — understanding how Kubernetes is built and operated
2. **Application delivery** — deploying workloads reliably through declarative workflows
3. **Security** — enforcing least privilege and secure service communication
4. **Reliability** — designing for health, recovery, and failure handling
5. **Observability** — understanding what is happening inside the cluster and service mesh

The goal is to build practical Kubernetes and cloud-native engineering depth across the full workload lifecycle.
