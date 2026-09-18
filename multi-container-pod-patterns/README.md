# Kubernetes Multi-Container Pod Patterns

## What This Does

This implementation demonstrates how multiple containers can cooperate inside a single Kubernetes Pod while remaining functionally separated. It covers init-container sequencing, logging sidecars, monitoring sidecars, cleanup sidecars, shared ephemeral storage, cross-container file exchange, and container-level resource monitoring.

The first workload uses an init container to generate application configuration and prepare shared Nginx log files before the main web container starts. A logging sidecar continuously consumes those access logs from the same `emptyDir` volume.

The second workload expands the pattern into a data-processing workflow where an init container prepares input data, a main container processes it, a monitoring sidecar observes results, and a cleanup sidecar removes temporary artifacts.

## Architecture

```text
+------------------------------------------------------------------+
|                    MULTI-CONTAINER POD                            |
|                                                                  |
|  Init Container                                                  |
|  +----------------------+                                        |
|  | configuration setup  |                                        |
|  | prepares shared data |                                        |
|  +----------+-----------+                                        |
|             |                                                    |
|             v                                                    |
|  +----------------------- emptyDir ----------------------------+  |
|  |                                                        |    |  |
|  |  config-volume                                         |    |  |
|  |  shared-logs                                           |    |  |
|  +-----------+--------------------------------------------+----+  |
|              |                                            |       |
|              v                                            v       |
|  +----------------------+                      +----------------+ |
|  |      web-app         |                      | log-sidecar    | |
|  |      Nginx           |---- access.log ---->| tail -F logs   | |
|  +----------------------+                      +----------------+ |
+------------------------------------------------------------------+


+------------------------------------------------------------------+
|                  ADVANCED MULTI-CONTAINER POD                    |
|                                                                  |
|  Init Container                                                  |
|  +----------------------+                                        |
|  | data-initializer     |                                        |
|  | input + metadata     |                                        |
|  +----------+-----------+                                        |
|             |                                                    |
|             v                                                    |
|  +-------------------------- emptyDir -------------------------+  |
|  |                         /data                              |  |
|  +--------+------------------+-------------------+-------------+  |
|           |                  |                   |                |
|           v                  v                   v                |
|  +---------------+   +----------------+   +------------------+   |
|  | main-app      |   | monitor-sidecar|   | cleanup-sidecar  |   |
|  | processes data|   | observes output|   | removes temp data|   |
|  +---------------+   +----------------+   +------------------+   |
+------------------------------------------------------------------+
```

## Prerequisites

- Ubuntu Linux
- Docker Engine
- kubectl
- Minikube
- Kubernetes cluster access
- curl
- jq
- sudo access
- Internet connectivity for container image retrieval

## Repository Structure

```text
multi-container-pod-patterns/
├── README.md
├── multi-container-pod.yaml
├── advanced-multi-container.yaml
└── evidence/
    ├── multi-container-init.log
    ├── multi-container-web.log
    ├── multi-container-sidecar.log
    ├── advanced-init.log
    ├── advanced-main.log
    ├── advanced-monitor.log
    ├── advanced-cleanup.log
    ├── multi-container-final.yaml
    ├── advanced-multi-container-final.yaml
    ├── pod-status.txt
    ├── multi-container-metrics.txt
    ├── advanced-multi-container-metrics.txt
    └── events.txt
```

## Setup & Installation

Install Minikube if required:

```bash
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64)
    MINIKUBE_ARCH="amd64"
    ;;
  aarch64|arm64)
    MINIKUBE_ARCH="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

curl -fL \
  "https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-${MINIKUBE_ARCH}" \
  -o /tmp/minikube

sudo install /tmp/minikube /usr/local/bin/minikube
rm -f /tmp/minikube
```

Start the local Kubernetes cluster:

```bash
minikube start \
  --driver=docker \
  --container-runtime=containerd \
  --cpus=2 \
  --memory=2200mb
```

Verify the cluster:

```bash
kubectl get nodes -o wide
```

## How to Reproduce

### 1. Deploy the init-container and logging-sidecar pattern

```bash
kubectl create namespace pod-patterns
kubectl apply -f multi-container-pod.yaml
```

Wait for readiness:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/multi-container-app \
  -n pod-patterns \
  --timeout=300s
```

### 2. Verify init-container completion

```bash
kubectl logs \
  multi-container-app \
  -n pod-patterns \
  -c config-setup
```

Inspect its termination state:

```bash
kubectl get pod multi-container-app \
  -n pod-patterns \
  -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}'
```

Expected:

```text
Completed
```

### 3. Verify initialized configuration

```bash
kubectl exec \
  multi-container-app \
  -n pod-patterns \
  -c web-app \
  -- cat /etc/app-config/app.conf
```

Expected configuration:

```text
server_name=web-app
log_level=info
port=8080
```

### 4. Verify shared logging volume

Inspect from the web container:

```bash
kubectl exec \
  multi-container-app \
  -n pod-patterns \
  -c web-app \
  -- ls -lah /var/log/nginx
```

Inspect from the logging sidecar:

```bash
kubectl exec \
  multi-container-app \
  -n pod-patterns \
  -c log-sidecar \
  -- ls -lah /var/log/nginx
```

Both containers reference the same `emptyDir` volume.

### 5. Generate HTTP traffic

Obtain the application Pod IP:

```bash
POD_IP="$(
  kubectl get pod multi-container-app \
    -n pod-patterns \
    -o jsonpath='{.status.podIP}'
)"
```

Create a temporary client:

```bash
kubectl run test-client \
  --image=busybox:stable \
  --restart=Never \
  -n pod-patterns \
  -- \
  /bin/sh -c "
    wget -q -O- http://${POD_IP}/ >/dev/null
    wget -q -O- http://${POD_IP}/nonexistent >/dev/null 2>&1 || true
    wget -q -O- http://${POD_IP}/ >/dev/null
  "
```

### 6. Verify sidecar log consumption

```bash
kubectl logs \
  multi-container-app \
  -n pod-patterns \
  -c log-sidecar
```

The sidecar continuously follows the Nginx access log using:

```text
tail -n 0 -F /var/log/nginx/access.log
```

### 7. Verify cross-container file exchange

Write from the main container:

```bash
kubectl exec \
  multi-container-app \
  -n pod-patterns \
  -c web-app \
  -- sh -c \
  'echo "shared-volume-test" > /var/log/nginx/shared.txt'
```

Read from the sidecar:

```bash
kubectl exec \
  multi-container-app \
  -n pod-patterns \
  -c log-sidecar \
  -- cat /var/log/nginx/shared.txt
```

Expected:

```text
shared-volume-test
```

### 8. Deploy the advanced multi-container pattern

```bash
kubectl apply \
  -f advanced-multi-container.yaml
```

Wait for readiness:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/advanced-multi-container \
  -n pod-patterns \
  --timeout=300s
```

### 9. Verify initialized data

```bash
kubectl logs \
  advanced-multi-container \
  -n pod-patterns \
  -c data-initializer
```

The initializer creates:

```text
/data/input/sample.txt
/data/input/metadata.txt
/data/tmp/sample.tmp
```

### 10. Verify main-container processing

```bash
kubectl exec \
  advanced-multi-container \
  -n pod-patterns \
  -c main-app \
  -- cat /data/output/processed.txt
```

The main container continuously processes the shared input and writes output into the same shared volume.

### 11. Verify monitoring sidecar

```bash
kubectl logs \
  advanced-multi-container \
  -n pod-patterns \
  -c monitor-sidecar \
  --tail=50
```

The monitoring sidecar observes:

- input files
- generated output
- processing timestamps
- shared directory state

### 12. Verify cleanup sidecar

Temporary files are stored under:

```text
/data/tmp
```

The cleanup sidecar periodically removes eligible `.tmp` artifacts while the other containers continue running.

Inspect its logs:

```bash
kubectl logs \
  advanced-multi-container \
  -n pod-patterns \
  -c cleanup-sidecar \
  --tail=50
```

### 13. Enable Metrics Server

```bash
minikube addons enable metrics-server
```

Wait for it:

```bash
kubectl rollout status \
  deployment/metrics-server \
  -n kube-system \
  --timeout=300s
```

### 14. Inspect per-container resource usage

First workload:

```bash
kubectl top pod multi-container-app \
  -n pod-patterns \
  --containers
```

Advanced workload:

```bash
kubectl top pod advanced-multi-container \
  -n pod-patterns \
  --containers
```

### 15. Troubleshoot individual containers

Inspect Pod state:

```bash
kubectl describe pod multi-container-app \
  -n pod-patterns
```

Inspect events:

```bash
kubectl get events \
  -n pod-patterns \
  --field-selector involvedObject.name=multi-container-app
```

Inspect the main process:

```bash
kubectl exec \
  multi-container-app \
  -n pod-patterns \
  -c web-app \
  -- ps aux
```

Inspect the logging sidecar:

```bash
kubectl exec \
  multi-container-app \
  -n pod-patterns \
  -c log-sidecar \
  -- ps aux
```

### 16. Clean up live resources

```bash
kubectl delete namespace pod-patterns
```

The local manifests and evidence files remain available after cluster cleanup.

## Tools Used

- Kubernetes
- kubectl
- Minikube
- Docker
- containerd
- Nginx
- BusyBox
- Init Containers
- Sidecar Containers
- `emptyDir` Volumes
- Metrics Server
- Bash
- jq

## Key Skills Demonstrated

- Designing multi-container Kubernetes Pods
- Controlling startup order with init containers
- Building sidecar-based logging patterns
- Coordinating containers through shared storage
- Implementing ephemeral `emptyDir` volumes
- Streaming application logs from a dedicated sidecar
- Sharing generated configuration across containers
- Validating cross-container file access
- Separating application, monitoring, and maintenance responsibilities
- Inspecting container-specific processes
- Tracking container restart counts
- Reading Kubernetes events for troubleshooting
- Monitoring per-container CPU and memory consumption
- Capturing reproducible operational evidence
- Managing short-lived Kubernetes resources cleanly

## Real-World Use Case

Multi-container Pod patterns are useful when tightly coupled processes need to share the same lifecycle, network namespace, or local storage while keeping responsibilities separated. A primary application may be accompanied by a logging agent, configuration generator, proxy, file synchronizer, monitoring process, or maintenance utility without embedding those capabilities directly into the application container.

The same patterns are commonly applicable to API services, AI inference workloads, internal platform components, observability agents, data-processing services, and service-mesh-style helpers.

## Lessons Learned

- Init containers provide deterministic startup sequencing and must complete successfully before normal containers begin.
- `emptyDir` volumes allow containers inside one Pod to exchange files without external persistent storage.
- Sidecars are most useful when they provide a capability closely tied to the main application lifecycle.
- Continuous log consumption with `tail -F` behaves more predictably than repeatedly polling the last few lines of a file.
- Container-level metrics require Metrics Server and cannot be assumed to exist in a fresh Kubernetes environment.
- Interactive testing can usually be replaced with deterministic temporary Pods for faster and repeatable validation.
- Cleanup behavior should be tested on a time scale suitable for the execution environment rather than relying on day-old files.
- Multiple containers inside one Pod should remain tightly coupled; independent services should generally use separate Pods.

## Troubleshooting Log

### Metrics API Unavailable in Fresh Cluster

`kubectl top` requires the Kubernetes Metrics API.

A fresh Minikube cluster did not provide that capability automatically.

Resolution:

```bash
minikube addons enable metrics-server
```

Metrics Server readiness was verified before collecting CPU and memory measurements.

### Interactive Client Replaced with Deterministic Traffic Generation

A manual workflow requiring an interactive temporary container and manually substituted Pod IP introduces unnecessary execution variance.

The validation was replaced with a non-interactive BusyBox Pod that automatically sends known requests to the target Pod IP.

This made access-log verification deterministic.

### Logging Sidecar Polling Behavior

A polling loop that repeatedly displays the last five lines can duplicate output and does not model a real log-streaming sidecar effectively.

The logging sidecar instead uses:

```text
tail -n 0 -F /var/log/nginx/access.log
```

This follows newly appended entries continuously.

### Cleanup Verification Timing

A cleanup rule based on files older than one day cannot realistically be demonstrated during a short environment session.

The cleanup behavior was adjusted to a minute-scale lifecycle so temporary artifact deletion could be proven during execution.

### Shared Volume Verification

Shared volume functionality was validated in both directions by:

- inspecting identical mounted paths from multiple containers
- writing a file from the primary container
- reading the same file from the sidecar
- verifying generated processing output from multiple containers

## Validation Evidence

The `evidence/` directory contains runtime validation captured before cleanup:

```text
multi-container-init.log
multi-container-web.log
multi-container-sidecar.log
advanced-init.log
advanced-main.log
advanced-monitor.log
advanced-cleanup.log
multi-container-final.yaml
advanced-multi-container-final.yaml
pod-status.txt
multi-container-metrics.txt
advanced-multi-container-metrics.txt
events.txt
```

These files preserve init-container output, application logs, sidecar behavior, final Pod specifications, Pod state, metrics, and Kubernetes events.

## Production Improvements

For production environments, consider:

- Pinning container images by digest
- Applying Pod Security Admission policies
- Adding explicit security contexts
- Setting read-only root filesystems where possible
- Applying resource requests and limits consistently
- Using structured logging instead of raw text parsing
- Shipping logs to centralized observability infrastructure
- Adding NetworkPolicies
- Using ConfigMaps or external configuration systems for non-sensitive configuration
- Using Secrets or external secret managers for credentials
- Adding persistent storage when data must survive Pod deletion
- Using Deployments instead of standalone Pods for restart and rollout management
