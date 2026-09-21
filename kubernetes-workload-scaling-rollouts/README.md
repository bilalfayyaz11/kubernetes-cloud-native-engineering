# Kubernetes Workload Scaling, Rollouts, and Resource Governance

## Overview

This implementation demonstrates production-oriented Kubernetes workload management across scaling, autoscaling, deployment lifecycle management, failure recovery, and namespace-level resource governance.

The environment uses a Kubernetes control plane with containerd, Flannel networking, Metrics Server, and native Kubernetes workload APIs.

The implementation validates:

- Declarative application deployment with Kubernetes Deployments
- ClusterIP service discovery and connectivity
- Manual horizontal replica scaling
- CPU-based Horizontal Pod Autoscaling
- Metrics Server integration
- Deterministic CPU pressure testing
- Automatic HPA scale-out and scale-down
- Rolling deployment updates
- Service availability during deployment transitions
- Failed image rollout diagnosis
- Deployment rollback recovery
- Revision-specific rollback
- CPU and memory requests and limits
- Namespace ResourceQuota enforcement
- Admission rejection of workloads exceeding quota

---

## Architecture

~~text
                         Kubernetes Control Plane
                                  |
                         +--------+--------+
                         |                 |
                         v                 v
                  Deployment API       Metrics API
                         |                 |
                         |                 v
                         |          Metrics Server
                         |                 |
                         v                 |
                  Replica Management <----+
                         |
          +--------------+---------------+
          |                              |
          v                              v
   nginx-deployment                  cpu-demo
   Manual Scaling                       |
   3 -> 5 -> 2                           v
                                   HorizontalPod
                                     Autoscaler
                                   1 -> N -> 1

                         Deployment Lifecycle
                                  |
                                  v
                               webapp
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
              Rolling Update              Failed Release
                    |                           |
                    v                           v
             Healthy Revision            ImagePull Failure
                                                |
                                                v
                                          Rollback Recovery

                       Namespace Governance
                                  |
                                  v
                           resource-demo
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
             ResourceQuota              Resource Requests
                                           and Limits
                    |
                    v
            API Admission Control
                    |
                    v
           Over-Quota Rejection
~~

---

## Kubernetes Environment

The environment was prepared with:

- Kubernetes v1.36
- kubeadm
- kubelet
- kubectl
- containerd 2.x
- Flannel CNI
- Metrics Server
- CRI v1 runtime validation with `crictl`

A containerd CRI configuration issue was identified during bootstrap and corrected before Kubernetes initialization.

The runtime was explicitly validated through:

~~bash
sudo crictl info
~~

The Kubernetes control plane was then initialized using the containerd CRI socket.

---

## 1. Deployment and Manual Horizontal Scaling

The first workload uses an NGINX Deployment with explicit resource requests and limits.

Initial replica count:

~~text
3
~~

The Deployment was manually scaled through:

~~text
3 replicas
     |
     v
5 replicas
     |
     v
2 replicas
~~

Scaling was performed using:

~~bash
kubectl scale deployment nginx-deployment --replicas=5
kubectl scale deployment nginx-deployment --replicas=2
~~

The final state was validated by comparing desired, ready, available, and updated replicas.

### Service Exposure

A `ClusterIP` Service provides internal connectivity to the NGINX workload.

Service backends were validated through EndpointSlices and an in-cluster HTTP connectivity test.

### Artifacts

- `nginx-deployment.yaml`
- `nginx-service.yaml`
- `manual-scaling-evidence.txt`

---

## 2. Horizontal Pod Autoscaling

CPU-based automatic scaling was implemented using the Kubernetes `autoscaling/v2` API.

### HPA Configuration

~~yaml
minReplicas: 1
maxReplicas: 6
target CPU utilization: 30%
~~

The workload defines:

~~yaml
resources:
  requests:
    cpu: 100m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 128Mi
~~

The HPA calculates utilization relative to the CPU request and automatically adjusts the Deployment replica count.

### Metrics Pipeline

The scaling path is:

~~text
Application Pods
      |
      v
    kubelet
      |
      v
Metrics Server
      |
      v
metrics.k8s.io
      |
      v
Horizontal Pod Autoscaler
      |
      v
Deployment Replica Count
~~

Metrics availability was validated using:

~~bash
kubectl top nodes
kubectl top pods
kubectl get hpa
~~

### CPU Pressure Validation

An HTTP-based load pattern initially generated insufficient CPU utilization to cross the configured HPA threshold.

The test was therefore made deterministic by temporarily running CPU-intensive work directly inside the target workload.

This produced measurable CPU utilization above the HPA target and allowed Kubernetes to demonstrate automatic scale-out.

After the scaling event was captured, the workload was returned to an idle state so HPA scale-down behavior could also be observed.

This validates both directions of the autoscaling control loop:

~~text
Low CPU
   |
   v
1 replica
   |
CPU pressure
   |
   v
HPA scale-out
   |
   v
Multiple replicas
   |
Pressure removed
   |
   v
HPA stabilization
   |
   v
Scale-down
   |
   v
1 replica
~~

### Artifacts

- `cpu-demo-deployment.yaml`
- `cpu-demo-service.yaml`
- `cpu-demo-hpa.yaml`
- `load-generator.yaml`
- `hpa-autoscaling-evidence.txt`

---

## 3. Rolling Deployment Updates

A separate four-replica web workload was configured with a rolling update strategy.

~~yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
~~

A readiness probe was also configured so replacement Pods are considered available only after the application is serving traffic.

### Baseline Release

~~text
nginx:1.27
~~

### Successful Update

The Deployment was updated to:

~~text
nginx:1.28
~~

Kubernetes progressively created the new ReplicaSet and replaced the old Pods while maintaining application availability.

Rollout state was monitored using:

~~bash
kubectl rollout status deployment/webapp
kubectl get pods -l app=webapp
kubectl rollout history deployment/webapp
~~

---

## 4. Failed Release and Rollback Recovery

A deliberately invalid container image was introduced:

~~text
nginx:1.28-invalid
~~

The resulting rollout stalled because Kubernetes could not pull the image.

Diagnostics included:

- Pod state inspection
- ReplicaSet inspection
- Container waiting reason
- Image pull error message
- Pod events
- Deployment availability during the failed rollout
- Rollout revision history

The existing healthy replicas continued serving the ClusterIP Service while the new revision failed.

### Rollback

The failed release was recovered using:

~~bash
kubectl rollout undo deployment/webapp
~~

The Deployment returned to the previous healthy image:

~~text
nginx:1.28
~~

Application connectivity was validated again after recovery.

### Revision-Specific Recovery

The Deployment was subsequently restored to its original revision:

~~bash
kubectl rollout undo deployment/webapp --to-revision=1
~~

This restored:

~~text
nginx:1.27
~~

The workflow demonstrates both immediate recovery from a failed release and precise historical revision recovery.

### Artifacts

- `webapp-deployment.yaml`
- `webapp-service.yaml`
- `rolling-update-rollback-evidence.txt`

---

## 5. Resource Requests and Limits

A dedicated namespace was created for resource-governed workloads:

~~text
resource-demo
~~

A three-replica NGINX Deployment was configured with explicit resource policies.

Per container:

~~yaml
requests:
  cpu: 200m
  memory: 256Mi

limits:
  cpu: 500m
  memory: 512Mi
~~

Resource requests provide Kubernetes scheduling requirements, while limits establish maximum container resource consumption.

---

## 6. Namespace ResourceQuota

The namespace was protected using a `ResourceQuota`.

~~yaml
hard:
  requests.cpu: "2"
  requests.memory: 2Gi
  limits.cpu: "4"
  limits.memory: 4Gi
  pods: "10"
~~

The quota constrains aggregate workload consumption inside the namespace.

Usage was inspected with:

~~bash
kubectl get resourcequota -n resource-demo
kubectl describe resourcequota compute-quota -n resource-demo
~~

This demonstrates namespace-level capacity governance independent of individual Pod configuration.

---

## 7. Quota Enforcement Test

Quota behavior was tested using a deliberately oversized Pod requesting:

~~yaml
requests:
  cpu: "2"
  memory: 2Gi

limits:
  cpu: "4"
  memory: 4Gi
~~

Because existing namespace workloads were already consuming resources, admitting this Pod would exceed the configured quota.

The Kubernetes API server rejected the request during admission.

This demonstrates an important distinction:

~~text
Resource Requests / Limits
        |
        v
Individual workload policy

ResourceQuota
        |
        v
Namespace aggregate policy

Admission Control
        |
        v
Reject resource creation when namespace quota would be exceeded
~~

The existing healthy workload remained unaffected by the rejected resource.

### Artifacts

- `resource-quota.yaml`
- `resource-limited-deployment.yaml`
- `quota-rejection.yaml`
- `resource-governance-evidence.txt`

---

## Operational Troubleshooting

### Container Runtime CRI Failure

During Kubernetes bootstrap, kubeadm initially failed with:

~~text
unknown service runtime.v1.RuntimeService
~~

The host was running containerd 2.x, while the initial runtime configuration did not expose the CRI v1 service correctly.

Resolution included:

- Regenerating the containerd 2.x configuration
- Ensuring CRI was enabled
- Configuring systemd cgroups
- Restarting containerd
- Validating CRI with `crictl info`
- Explicitly supplying the containerd CRI socket to kubeadm

This established a working Kubernetes-to-container-runtime path before control-plane initialization.

---

### HPA Not Scaling

The first load generation approach produced approximately:

~~text
1% CPU utilization
~~

against an HPA target of:

~~text
30%
~~

The autoscaler correctly kept the Deployment at one replica because the scaling threshold was never crossed.

The test was corrected by applying deterministic CPU pressure to the target workload.

This generated a strong metrics signal and demonstrated actual HPA scale-out behavior.

---

### Failed Rolling Update

The invalid image revision resulted in an image pull failure.

Investigation used:

~~bash
kubectl get pods
kubectl describe pod
kubectl get replicasets
kubectl rollout history deployment/webapp
~~

The Deployment was recovered through Kubernetes revision history rather than manually rebuilding the workload.

---

## Key Kubernetes Concepts Demonstrated

### Declarative Workload Management

Deployments continuously reconcile actual cluster state with desired state.

### Horizontal Scaling

Replica counts can be modified manually or automatically in response to metrics.

### Metrics-Driven Automation

Metrics Server exposes resource utilization to Kubernetes autoscaling controllers.

### Rolling Updates

Deployments replace application instances incrementally while preserving availability.

### Rollback Safety

ReplicaSet history enables rapid recovery from defective releases.

### Resource-Aware Scheduling

CPU and memory requests influence Kubernetes scheduling decisions.

### Resource Limits

Limits prevent individual containers from consuming unrestricted resources.

### Namespace Governance

ResourceQuota constrains total resource allocation within a namespace.

### Admission Enforcement

Kubernetes rejects new workloads when their requested resources violate namespace policy.

---

## Repository Contents

~~text
kubernetes-workload-scaling-rollouts/
├── README.md
├── nginx-deployment.yaml
├── nginx-service.yaml
├── manual-scaling-evidence.txt
├── cpu-demo-deployment.yaml
├── cpu-demo-service.yaml
├── cpu-demo-hpa.yaml
├── load-generator.yaml
├── hpa-autoscaling-evidence.txt
├── webapp-deployment.yaml
├── webapp-service.yaml
├── rolling-update-rollback-evidence.txt
├── resource-quota.yaml
├── resource-limited-deployment.yaml
├── quota-rejection.yaml
└── resource-governance-evidence.txt
~~

---

## Skills Demonstrated

- Kubernetes Deployment management
- ReplicaSet lifecycle management
- Manual horizontal scaling
- Horizontal Pod Autoscaler configuration
- `autoscaling/v2`
- Kubernetes Metrics API
- Metrics Server troubleshooting
- CPU utilization analysis
- Service and EndpointSlice validation
- Rolling deployment strategies
- Readiness-based release safety
- Failed rollout diagnosis
- Kubernetes revision history
- Deployment rollback
- Resource requests and limits
- ResourceQuota
- Kubernetes admission enforcement
- containerd CRI troubleshooting
- kubeadm cluster initialization
- Operational evidence collection

---

## Real-World Relevance

These techniques apply directly to:

- Kubernetes platform engineering
- DevOps and DevSecOps operations
- AIOps infrastructure
- Production workload scaling
- Capacity optimization
- Release engineering
- Continuous delivery
- Incident recovery
- Multi-tenant resource governance
- Cluster reliability engineering

The combination of autoscaling, rollout controls, failure recovery, scheduling constraints, and namespace governance represents the operational controls required to run containerized workloads reliably in production Kubernetes environments.
