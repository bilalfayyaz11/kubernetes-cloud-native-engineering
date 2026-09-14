# Kubernetes Workload Management

This implementation demonstrates core Kubernetes workload-management capabilities using a local Minikube cluster.

The environment focuses on declarative application deployment, service exposure, scaling, failure recovery, configuration management, health checks, resource controls, observability, and rolling updates.

## Architecture

```text
                         ┌─────────────────────┐
                         │       Client        │
                         └──────────┬──────────┘
                                    │
                                    ▼
                         ┌─────────────────────┐
                         │   NodePort Service  │
                         │   nginx-service     │
                         └──────────┬──────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
               nginx Pod       nginx Pod       nginx Pod
                    │               │               │
                    └───────────────┴───────────────┘
                                    │
                                    ▼
                         Deployment Controller
```

## What Was Implemented

### Kubernetes Cluster

A local Kubernetes cluster was created using Minikube with the Docker driver.

The cluster was managed using `kubectl` and validated through:

- cluster information inspection
- node readiness checks
- system Pod inspection
- kubeconfig context validation

## Declarative Application Deployment

An nginx workload was deployed using a Kubernetes Deployment manifest.

The Deployment defines:

- three application replicas
- container image version
- exposed container port
- CPU requests and limits
- memory requests and limits
- label selectors
- desired workload state

Example resource controls:

```text
Requests:
  CPU:    250m
  Memory: 64Mi

Limits:
  CPU:    500m
  Memory: 128Mi
```

The Deployment controller maintains the declared replica count and continuously reconciles the actual cluster state.

## Service Exposure

A NodePort Service was created to expose the nginx workload.

The Service uses label selectors to dynamically discover matching Pods.

This separates application networking from individual Pod addresses and provides a stable service abstraction.

## Horizontal Scaling

The Deployment was manually scaled from three replicas to five replicas.

Kubernetes created additional Pods automatically to satisfy the new desired state.

The workload was then scaled down to two replicas, and Kubernetes removed excess Pods automatically.

This demonstrated declarative replica management without manually creating or deleting individual containers.

## Self-Healing

A running nginx Pod was deliberately deleted to simulate workload failure.

Because the Deployment declared a desired replica count of two, Kubernetes detected the missing replica and automatically created a replacement Pod.

This demonstrated controller-based reconciliation and self-healing behavior.

## Pod Logging and Debugging

Operational troubleshooting was performed using standard Kubernetes commands.

The workflow included:

- viewing application logs
- selecting individual Pods
- executing commands inside running containers
- validating nginx configuration
- inspecting running workload state

These capabilities provide direct visibility into application behavior inside the cluster.

## Resource Monitoring

The Minikube Metrics Server addon was enabled to provide resource telemetry.

Resource consumption was inspected using:

```text
kubectl top nodes
kubectl top pods
```

This provided visibility into CPU and memory utilization at both node and workload level.

## ConfigMaps and Secrets

A ConfigMap was created to represent non-sensitive runtime configuration.

A Secret was created to demonstrate Kubernetes-native handling of sensitive configuration values.

This separates runtime configuration from container images and allows application configuration to be independently managed.

## Health Checks

A separate Deployment was configured with:

- liveness probe
- readiness probe
- CPU requests
- CPU limits
- memory requests
- memory limits

The readiness probe determines whether a Pod is ready to receive traffic.

The liveness probe allows Kubernetes to detect unhealthy containers and trigger recovery actions.

## Rolling Updates

The health-enabled nginx Deployment was updated from:

```text
nginx:1.21
```

to:

```text
nginx:1.22
```

The Deployment rollout was monitored until completion.

Rollout history was also inspected to demonstrate Kubernetes-native deployment lifecycle management.

This allows application versions to be replaced incrementally while maintaining the desired workload state.

## Kubernetes vs Docker Swarm

A comparison was created to evaluate both orchestration platforms across operational dimensions.

| Capability | Kubernetes | Docker Swarm |
|---|---|---|
| Setup complexity | Higher | Lower |
| Learning curve | Steeper | Gentler |
| Replica management | Advanced | Basic |
| Self-healing | Controller-driven | Service-driven |
| Service discovery | Kubernetes Services and DNS | Built-in DNS |
| Autoscaling | Extensive | Limited |
| Networking | Highly extensible | Simpler |
| Configuration | ConfigMaps and Secrets | Configs and Secrets |
| Health management | Native probes | Container health checks |
| Rolling updates | Advanced | Supported |
| Monitoring ecosystem | Extensive | Smaller |
| Cloud integration | Extensive | Limited |
| Ecosystem | Large cloud-native ecosystem | Docker-focused |

Kubernetes provides greater flexibility, extensibility, automation, and ecosystem integration.

Docker Swarm provides a simpler operational model and may be appropriate for smaller Docker-centric environments.

## Repository Contents

```text
kubernetes-workload-management/
├── README.md
├── advanced-operations-summary.md
├── command-comparison.txt
├── decision-matrix.md
├── nginx-deployment.yaml
├── nginx-service.yaml
├── nginx-with-probes.yaml
└── orchestration-comparison.md
```

## Key Kubernetes Concepts Demonstrated

### Pods

Pods provide the runtime abstraction used to execute application containers.

### Deployments

Deployments manage replica counts, workload reconciliation, application updates, and rollout history.

### Services

Services provide stable networking and traffic distribution across dynamically changing Pods.

### Desired State

Kubernetes continuously attempts to make actual cluster state match the declared configuration.

### Resource Requests and Limits

Requests influence scheduling decisions.

Limits constrain the maximum resources a container can consume.

### Health Probes

Readiness and liveness probes allow Kubernetes to make workload-health decisions automatically.

### Configuration Management

ConfigMaps and Secrets separate configuration data from application images.

### Self-Healing

Controllers automatically restore missing workload replicas.

### Rolling Updates

Deployments allow application versions to be changed gradually while maintaining service availability.

## Operational Model

The central Kubernetes operating model demonstrated here is declarative infrastructure management.

Instead of manually controlling individual containers, operators define resources such as:

```text
Deployment
Service
ConfigMap
Secret
Probe
Resource Limits
Replica Count
```

Kubernetes controllers then continuously reconcile those definitions with the actual environment.

## Key Takeaway

Kubernetes is more than a container execution platform.

It provides a control system for maintaining application state across deployment, scaling, failure recovery, networking, configuration, health management, resource governance, and application updates.

This implementation demonstrates the fundamental workload-management patterns used across modern cloud-native environments.
