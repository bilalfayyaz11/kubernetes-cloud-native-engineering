# Kubernetes Application Observability

## Overview

This implementation demonstrates practical Kubernetes application observability using native cluster tooling and workload-level diagnostics.

The environment was built from a fresh Ubuntu host and configured with Kubernetes, Flannel, and Metrics Server before implementing:

- Startup probes
- Readiness probes
- Liveness probes
- Service endpoint validation
- Metrics Server
- `kubectl top`
- Pod and node resource monitoring
- Controlled CPU load generation
- Application log analysis
- Previous-container log inspection
- `kubectl exec` debugging
- Container configuration extraction
- Kubernetes event analysis
- Deliberately broken workload diagnosis
- Multi-container logging
- Per-container metrics
- Finite observability monitoring
- Simple alert simulation

The focus is not only on deploying applications, but on determining whether workloads are healthy, ready to receive traffic, consuming abnormal resources, restarting, failing to mount dependencies, or producing operational warning signals.

---

## Architecture

~~text
                         Kubernetes API
                              |
            +-----------------+------------------+
            |                 |                  |
            v                 v                  v
       kubelet probes    Metrics Server     Kubernetes Events
            |                 |                  |
            v                 v                  v
    Workload Health      Resource Usage      Failure Signals
            |                 |                  |
            +-----------------+------------------+
                              |
                              v
                        kubectl tooling
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
     kubectl logs        kubectl top        kubectl exec
          |                   |                   |
          v                   v                   v
    Log Analysis       CPU / Memory         Live Debugging
~~

---

## Environment

The cluster was prepared using:

- Ubuntu 24.04
- Kubernetes v1.36
- kubeadm
- kubelet
- kubectl
- containerd 2.x
- Flannel CNI
- Metrics Server
- crictl

The runtime and cluster were validated before observability workloads were deployed.

---

## Cluster Bootstrap

The original environment provided `kubectl` but no active Kubernetes cluster.

The cluster was therefore initialized with kubeadm using:

~~text
Pod network CIDR: 10.244.0.0/16
CRI socket: unix:///run/containerd/containerd.sock
~~

containerd was configured with:

~~text
SystemdCgroup = true
~~

and CRI availability was validated using:

~~bash
sudo crictl info
~~

Flannel was then installed to provide Pod networking.

Because the environment contained a single node, the control-plane taint was removed so application workloads could be scheduled.

---

## Metrics Server

Metrics Server was installed to provide resource metrics through the Kubernetes Metrics API.

Validation included:

~~bash
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods -A
~~

The cloud VM environment required Metrics Server to connect to the kubelet using the node's internal address and tolerate the kubelet certificate configuration.

The resulting environment supports live CPU and memory inspection for nodes, Pods, and individual containers.

---

## Health Probe Strategy

The primary web workload uses all three Kubernetes health-probe mechanisms.

### Startup Probe

The startup probe determines whether the application has completed initialization.

~~yaml
startupProbe:
  httpGet:
    path: /
    port: 80
~~

This prevents liveness checks from restarting a workload while it is still starting.

---

### Readiness Probe

The readiness probe determines whether a Pod should receive Service traffic.

~~yaml
readinessProbe:
  httpGet:
    path: /
    port: 80
~~

A Pod that fails readiness can remain running while being removed from active Service endpoints.

---

### Liveness Probe

The liveness probe determines whether Kubernetes should restart the container.

~~yaml
livenessProbe:
  httpGet:
    path: /
    port: 80
~~

Repeated liveness failures result in container restart.

---

## Healthy Application Validation

The healthy application runs as:

~~text
Deployment: webapp-with-probes
Replicas:   2
Service:    webapp-service
~~

Validation included:

- Deployment rollout success
- Pod Ready state
- probe configuration inspection
- Service creation
- EndpointSlice population
- internal HTTP connectivity

This verifies both workload health and traffic eligibility.

---

## Controlled Probe Failure

A separate workload named:

~~text
failing-webapp
~~

uses intentionally invalid probe paths:

~~text
/nonexistent
~~

This produces two distinct behaviors.

### Readiness Failure

The container remains excluded from Ready state.

This demonstrates that readiness controls traffic participation independently from process execution.

### Liveness Failure

Repeated failed liveness checks cause Kubernetes to restart the container.

The restart counter and probe events were observed to verify the behavior.

---

## Resource Monitoring

Resource consumption is inspected using:

~~bash
kubectl top nodes
kubectl top pods
kubectl top pods --sort-by=cpu
kubectl top pods --sort-by=memory
~~

This enables quick comparison of resource usage across cluster workloads.

---

## Controlled CPU Load

A dedicated workload:

~~text
cpu-intensive
~~

generates sustained CPU activity inside a defined resource boundary.

Resource configuration:

~~text
CPU request:     100m
CPU limit:       500m
Memory request:  32Mi
Memory limit:    96Mi
~~

The workload provides a predictable high-consumption target for comparison with normal application Pods.

This makes `kubectl top` useful as an operational diagnostic rather than merely displaying idle workloads.

---

## Finite Resource Monitoring

The reusable script:

~~text
scripts/monitor-resources.sh
~~

collects a fixed number of resource snapshots rather than running forever.

It reports:

- Node usage
- Highest CPU-consuming Pods
- Highest memory-consuming Pods

Example:

~~bash
./scripts/monitor-resources.sh 3 5
~~

This performs three samples five seconds apart and exits automatically.

---

## Application Log Analysis

The implementation demonstrates multiple forms of Kubernetes log inspection.

### Workload Logs

~~bash
kubectl logs <pod>
~~

### Label-Based Logs

~~bash
kubectl logs -l app=webapp
~~

### Timestamped Logs

~~bash
kubectl logs <pod> --timestamps
~~

### Tail Selection

~~bash
kubectl logs <pod> --tail=30
~~

### Previous Container Logs

~~bash
kubectl logs failing-webapp --previous
~~

Previous-container logs are particularly useful after liveness-triggered restarts.

---

## Custom Structured Log Generation

The `logging-app` workload emits regular operational messages along with simulated warning and error conditions.

Examples:

~~text
INFO application-running
WARNING simulated-high-memory-usage
ERROR simulated-application-error
~~

The logs are filtered into dedicated evidence using standard command-line tooling.

This demonstrates how operational signals can be separated from normal application output.

---

## Live Container Debugging

Running containers were inspected with `kubectl exec`.

Examples include:

~~bash
kubectl exec <pod> -- whoami
kubectl exec <pod> -- pwd
kubectl exec <pod> -- df -h
kubectl exec <pod> -- nginx -v
kubectl exec <pod> -- ls -la /usr/share/nginx/html
~~

This provides runtime information without requiring SSH access to the container.

---

## Container Configuration Extraction

The nginx configuration was copied from a running workload using:

~~bash
kubectl exec <pod> -- cat /etc/nginx/nginx.conf
~~

The resulting configuration was stored locally for inspection.

This technique is useful when diagnosing drift between expected and running application configuration.

---

## Deliberately Broken Workload

The `problematic-app` workload references:

~~text
ConfigMap: nonexistent-config
~~

Because that ConfigMap does not exist, the Pod cannot mount its required volume.

The failure is diagnosed using:

~~bash
kubectl get pod problematic-app
kubectl describe pod problematic-app
kubectl get events --sort-by=.metadata.creationTimestamp
~~

Expected signals include:

~~text
FailedMount
MountVolume
configmap not found
~~

This demonstrates how Kubernetes events reveal scheduling and startup problems that application logs cannot explain.

---

## Why Logs Alone Are Not Enough

A Pod that never starts may not produce useful application logs.

For example, a missing ConfigMap prevents the container from reaching normal execution.

In that situation the diagnostic hierarchy becomes:

~~text
kubectl get pod
        |
        v
kubectl describe pod
        |
        v
Kubernetes Events
        |
        v
container logs, if available
~~

This distinction is important in production troubleshooting.

---

## Multi-Container Observability

The multi-container workload contains:

~~text
web-server
log-processor
~~

Each container has an independent log stream.

Container-specific logs are collected with:

~~bash
kubectl logs multi-container-app -c web-server
kubectl logs multi-container-app -c log-processor
~~

Combined logs are collected with:

~~bash
kubectl logs multi-container-app \
  --all-containers=true \
  --prefix
~~

The prefix identifies which container generated each message.

---

## Per-Container Metrics

Metrics Server also enables container-level usage inspection:

~~bash
kubectl top pod multi-container-app --containers
~~

This allows operators to identify which container inside a Pod is consuming CPU or memory rather than treating the Pod as a single resource consumer.

---

## Observability Monitor

The reusable script:

~~text
scripts/observability-monitor.sh
~~

collects:

- Node metrics
- Top CPU-consuming Pods
- Top memory-consuming Pods
- healthy webapp state
- failing probe restart state
- CPU-intensive workload metrics
- multi-container metrics
- recent Warning events

Unlike an endless monitoring loop, the script accepts a finite sample count and exits cleanly.

Example:

~~bash
./scripts/observability-monitor.sh 5 10
~~

---

## Alert Simulation

The script:

~~text
scripts/check-observability-alerts.sh
~~

evaluates simple operational conditions including:

- failing workload readiness
- container restart count
- problematic Pod state
- current Warning-event count

Example alerts:

~~text
ALERT: failing-webapp is not Ready
ALERT: failing-webapp has restarted
ALERT: problematic-app phase=Pending
~~

This is intentionally lightweight and demonstrates how observable Kubernetes conditions can be converted into automated checks.

It is not presented as a replacement for a production monitoring platform.

---

## Observability Signals Demonstrated

The implementation covers four major operational signal categories.

### Health

~~text
Startup
Readiness
Liveness
Restarts
~~

### Resources

~~text
Node CPU
Node memory
Pod CPU
Pod memory
Container CPU
Container memory
~~

### Logs

~~text
Normal application logs
WARNING messages
ERROR messages
Previous-container logs
Multi-container logs
~~

### Cluster Diagnostics

~~text
Pod conditions
Deployment status
Service endpoints
Events
Volume-mount failures
Container runtime state
~~

---

## Troubleshooting Workflow

A practical diagnostic sequence demonstrated in this implementation is:

~~text
Application Problem
       |
       v
kubectl get pods
       |
       v
kubectl describe pod
       |
       +----------+
       |          |
       v          v
    Events       Logs
       |          |
       +-----+----+
             |
             v
        kubectl exec
             |
             v
      Runtime inspection
             |
             v
       Resource metrics
~~

This combines Kubernetes control-plane information with application-level evidence.

---

## Evidence Files

Operational evidence produced during the implementation includes:

~~text
observability-environment-evidence.txt
health-probe-evidence.txt
resource-observability-evidence.txt
resource-monitor-report.txt
webapp-all-logs.txt
webapp-selected-pod-logs.txt
webapp-after-traffic-logs.txt
failing-webapp-previous-logs.txt
logging-app-full.txt
logging-app-warnings.txt
logging-app-errors.txt
nginx-debug-evidence.txt
logging-app-debug-evidence.txt
problematic-app-describe.txt
problematic-app-logs.txt
kubernetes-events.txt
application-debugging-evidence.txt
multi-container-web-server-logs.txt
multi-container-log-processor-logs.txt
multi-container-combined-logs.txt
final-resource-metrics.txt
observability-monitor-report.txt
observability-alert-report.txt
final-observability-evidence.txt
~~

---

## Repository Structure

~~text
kubernetes-application-observability/
├── README.md
├── observability-environment-evidence.txt
├── health-probe-evidence.txt
├── resource-observability-evidence.txt
├── resource-monitor-report.txt
├── webapp-all-logs.txt
├── webapp-selected-pod-logs.txt
├── webapp-after-traffic-logs.txt
├── failing-webapp-previous-logs.txt
├── logging-app-full.txt
├── logging-app-warnings.txt
├── logging-app-errors.txt
├── nginx-debug-evidence.txt
├── nginx-config-backup.conf
├── logging-app-debug-evidence.txt
├── problematic-app-describe.txt
├── problematic-app-logs.txt
├── kubernetes-events.txt
├── application-debugging-evidence.txt
├── multi-container-web-server-logs.txt
├── multi-container-log-processor-logs.txt
├── multi-container-combined-logs.txt
├── final-resource-metrics.txt
├── observability-monitor-report.txt
├── observability-alert-report.txt
├── final-observability-evidence.txt
├── manifests/
│   ├── app-with-probes.yaml
│   ├── webapp-service.yaml
│   ├── failing-probes.yaml
│   ├── cpu-intensive.yaml
│   ├── logging-app.yaml
│   ├── problematic-app.yaml
│   └── multi-container-pod.yaml
└── scripts/
    ├── monitor-resources.sh
    ├── observability-monitor.sh
    └── check-observability-alerts.sh
~~

---

## Skills Demonstrated

- Kubernetes observability
- kubeadm
- containerd
- Flannel CNI
- Metrics Server
- Kubernetes Metrics API
- Startup probes
- Readiness probes
- Liveness probes
- `kubectl top`
- CPU and memory analysis
- Resource requests and limits
- Kubernetes logging
- Previous-container logs
- Multi-container logs
- `kubectl exec`
- Runtime debugging
- Configuration extraction
- Pod conditions
- Kubernetes Events
- Volume mount troubleshooting
- Service and EndpointSlice validation
- Container-level metrics
- Operational monitoring
- Alert-condition simulation

---

## Operational Relevance

These techniques apply directly to:

- Kubernetes operations
- Site Reliability Engineering
- DevOps
- Platform engineering
- AIOps infrastructure
- application incident response
- production workload debugging
- resource optimization
- reliability engineering

The implementation demonstrates an end-to-end operational workflow:

~~text
Deploy
  ->
Health Check
  ->
Route Traffic
  ->
Measure Resources
  ->
Analyze Logs
  ->
Inspect Runtime
  ->
Detect Failure
  ->
Correlate Events
  ->
Generate Alerts
~~

The key outcome is the ability to determine not simply whether a Kubernetes resource exists, but whether the application is actually healthy, routable, resource-efficient, and diagnosable during failure.
