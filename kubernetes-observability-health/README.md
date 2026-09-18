# Kubernetes Observability and Health Checks

## Overview

This implementation demonstrates application health management and runtime observability in Kubernetes.

It covers:

- startup probes
- readiness probes
- liveness probes
- automatic container restart behavior
- readiness-based traffic eligibility
- Metrics Server
- Pod and node resource metrics
- current and previous container logs
- Kubernetes event inspection
- Pod failure diagnosis
- Deployment-level observability
- replica scaling
- constrained-resource inspection
- runtime evidence capture
- cleanup with local artifact preservation

## Architecture

```text
                            +---------------------+
                            |    Kubernetes       |
                            |      Cluster        |
                            +----------+----------+
                                       |
               +-----------------------+-----------------------+
               |                       |                       |
               v                       v                       v
        +-------------+         +-------------+         +-------------+
        | Startup     |         | Readiness   |         | Liveness    |
        | Probe       |         | Probe       |         | Probe       |
        +------+------+         +------+------+         +------+------+
               |                       |                       |
               |                       |                       |
               v                       v                       v
        App startup gate        Traffic eligibility       Restart decision
                                                               |
                                                               v
                                                        Container restart


                       +------------------------------+
                       |        Metrics Server        |
                       +---------------+--------------+
                                       |
                                       v
                           +-----------------------+
                           |     kubectl top       |
                           +-----------+-----------+
                                       |
                         +-------------+-------------+
                         |                           |
                         v                           v
                   Pod metrics                 Node metrics


              +---------------------------------------------+
              |              Debugging Flow                 |
              +---------------------------------------------+
              | kubectl get                                 |
              | kubectl describe                            |
              | kubectl logs                                |
              | kubectl logs --previous                     |
              | kubectl get events                          |
              +---------------------------------------------+
```

## Repository Structure

```text
kubernetes-observability-health/
├── README.md
├── basic-app.yaml
├── app-with-liveness.yaml
├── app-with-readiness.yaml
├── app-with-all-probes.yaml
├── resource-intensive-app.yaml
├── failing-app.yaml
├── fixed-app.yaml
├── web-deployment.yaml
├── resource-constrained-app.yaml
└── evidence/
    ├── node-metrics.txt
    ├── pod-metrics.txt
    ├── resource-intensive-container-metrics.txt
    ├── resource-intensive-app-final.yaml
    ├── metrics-server-deployment.txt
    ├── metrics-server-pods.txt
    ├── failing-app-describe.txt
    ├── failing-app-events.txt
    ├── failing-app-current.log
    ├── failing-app-previous.log
    ├── failing-app-final.yaml
    ├── fixed-app-describe.txt
    ├── fixed-app-final.yaml
    ├── web-deployment-logs-before-scale.txt
    ├── web-deployment-pods-describe.txt
    ├── resource-constrained-app-describe.txt
    ├── resource-constrained-app.log
    ├── resource-constrained-app-metrics.txt
    ├── web-deployment-metrics.txt
    ├── node-metrics-final.txt
    ├── web-deployment-final.yaml
    ├── final-pod-inventory.txt
    └── final-events.txt
```

## Prerequisites

- Ubuntu Linux
- Docker Engine
- kubectl
- Minikube
- Metrics Server
- curl
- jq
- sudo access

## Environment Setup

Start Minikube:

```bash
minikube start \
  --driver=docker \
  --container-runtime=containerd \
  --cpus=2 \
  --memory=2200mb
```

Verify:

```bash
kubectl get nodes -o wide
```

## Namespace

The workloads use:

```text
observability-health
```

Create it with:

```bash
kubectl create namespace observability-health
```

## Baseline Pod

The baseline workload provides a healthy Nginx container with resource requests and limits.

Apply:

```bash
kubectl apply -f basic-app.yaml
```

Verify:

```bash
kubectl get pod basic-web-app \
  -n observability-health
```

## Liveness Probe

A liveness probe determines whether a container should continue running.

Example:

```yaml
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 3
```

If the liveness probe repeatedly fails, kubelet restarts the container.

Inspect:

```bash
kubectl describe pod app-with-liveness \
  -n observability-health
```

Restart count:

```bash
kubectl get pod app-with-liveness \
  -n observability-health \
  -o jsonpath='{.status.containerStatuses[0].restartCount}'
```

## Readiness Probe

A readiness probe determines whether the Pod should receive traffic.

Example:

```yaml
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 2
  periodSeconds: 3
  timeoutSeconds: 2
  failureThreshold: 3
```

A failed readiness probe does not automatically restart the container.

Instead:

```text
Pod Running
+
Ready = false
```

which removes it from normal Service traffic eligibility.

## Startup Probe

Startup probes protect slow-starting applications from premature liveness failures.

Example:

```yaml
startupProbe:
  httpGet:
    path: /
    port: 80
  periodSeconds: 2
  timeoutSeconds: 2
  failureThreshold: 15
```

Until the startup probe succeeds, liveness and readiness probing does not proceed normally.

## All-Probe Pattern

The combined workload demonstrates:

```text
startup
   |
   v
application initialization
   |
   v
readiness + liveness
```

This separates startup tolerance from steady-state health behavior.

## Metrics Server

Enable Metrics Server in Minikube:

```bash
minikube addons enable metrics-server
```

Verify:

```bash
kubectl get deployment metrics-server \
  -n kube-system
```

Check metrics API:

```bash
kubectl top nodes
```

## Metrics Propagation Delay

Metrics for newly created Pods are not always available immediately.

This can produce:

```text
error: metrics not available yet
```

even when the workload itself is healthy.

A safer validation pattern is:

```bash
for i in $(seq 1 30); do
    if kubectl top pod resource-intensive-app \
      -n observability-health; then
        break
    fi

    sleep 5
done
```

This treats metrics availability as an eventually consistent monitoring signal rather than an immediate workload-health check.

## Pod Metrics

View all Pods:

```bash
kubectl top pods \
  -n observability-health
```

Inspect one Pod:

```bash
kubectl top pod resource-intensive-app \
  -n observability-health
```

Per-container metrics:

```bash
kubectl top pod resource-intensive-app \
  -n observability-health \
  --containers
```

Label-filtered metrics:

```bash
kubectl top pods \
  -n observability-health \
  -l app=resource-test
```

## Node Metrics

```bash
kubectl top nodes
```

Inspect allocation:

```bash
kubectl describe node
```

This allows comparison between:

- requested resources
- configured limits
- actual recent usage
- node capacity
- node allocatable resources

## Intentional Probe Failure

The failing workload intentionally uses invalid HTTP paths:

```yaml
livenessProbe:
  httpGet:
    path: /nonexistent-path
    port: 80

readinessProbe:
  httpGet:
    path: /also-nonexistent
    port: 80
```

This creates two different observable effects.

## Readiness Failure Behavior

Expected:

```text
container process = running
Pod phase         = Running
Ready             = false
```

Kubernetes emits unhealthy probe events, but readiness failure alone does not require a restart.

## Liveness Failure Behavior

Repeated liveness failures cause kubelet to restart the container.

Verify:

```bash
kubectl get pod failing-app \
  -n observability-health \
  -o jsonpath='{.status.containerStatuses[0].restartCount}'
```

A restart count greater than zero proves liveness-triggered recovery behavior.

## Debugging with kubectl describe

```bash
kubectl describe pod failing-app \
  -n observability-health
```

Important sections include:

- container state
- restart count
- liveness configuration
- readiness configuration
- Events

## Kubernetes Events

```bash
kubectl get events \
  -n observability-health \
  --field-selector involvedObject.name=failing-app \
  --sort-by='.metadata.creationTimestamp'
```

Probe problems commonly appear as:

```text
Reason: Unhealthy
```

with messages describing readiness or liveness failures.

## Current Logs

```bash
kubectl logs failing-app \
  -n observability-health \
  --timestamps
```

## Previous Container Logs

After a liveness restart:

```bash
kubectl logs failing-app \
  -n observability-health \
  --previous \
  --timestamps
```

`--previous` is especially useful when the current container is healthy or newly restarted but the previous instance contains diagnostic information.

## Corrected Workload

The fixed workload changes both health checks to valid paths:

```yaml
httpGet:
  path: /
  port: 80
```

Expected state:

```text
Ready=true
RestartCount=0
```

Verify:

```bash
kubectl get pod fixed-app \
  -n observability-health
```

## Deployment-Level Observability

A Deployment with multiple replicas demonstrates observability beyond standalone Pods.

Initial state:

```text
replicas: 3
```

Deploy:

```bash
kubectl apply -f web-deployment.yaml
```

Monitor rollout:

```bash
kubectl rollout status \
  deployment/web-deployment \
  -n observability-health
```

## Label-Filtered Pod Inspection

```bash
kubectl get pods \
  -n observability-health \
  -l app=web-app
```

## Aggregated Logs

```bash
kubectl logs \
  -n observability-health \
  -l app=web-app \
  --tail=20 \
  --prefix=true
```

This allows logs from multiple replicas to be inspected in one command.

## Deployment Scaling

Scale from three to five replicas:

```bash
kubectl scale deployment web-deployment \
  -n observability-health \
  --replicas=5
```

Verify:

```bash
kubectl get deployment web-deployment \
  -n observability-health
```

Expected:

```text
READY 5/5
```

## Metrics After Scaling

New replicas can take several seconds before appearing in Metrics Server.

A retry loop should be used rather than assuming metrics are immediately available.

Example:

```bash
for i in $(seq 1 30); do
    COUNT="$(
      kubectl top pods \
        -n observability-health \
        -l app=web-app \
        --no-headers \
        2>/dev/null \
      | wc -l
    )"

    [ "$COUNT" -ge 5 ] && break

    sleep 5
done
```

## Resource Constraints

The constrained workload uses:

```yaml
resources:
  requests:
    memory: "10Mi"
    cpu: "10m"
  limits:
    memory: "20Mi"
    cpu: "20m"
```

These values are intentionally restrictive.

However, low limits alone do not guarantee a failure for an idle Nginx process.

The correct observation is therefore based on:

- Pod phase
- readiness
- restart count
- events
- logs
- actual metrics

rather than assuming the container must crash.

## Evidence Capture

The `evidence/` directory preserves runtime data before resource cleanup.

Examples include:

```text
node-metrics.txt
pod-metrics.txt
failing-app-events.txt
failing-app-current.log
failing-app-previous.log
fixed-app-final.yaml
web-deployment-metrics.txt
web-deployment-final.yaml
final-pod-inventory.txt
final-events.txt
```

This allows the operational behavior to be reviewed after the Kubernetes namespace has been removed.

## Troubleshooting Lessons

### Metrics Not Available Immediately

Observed:

```text
error: metrics not available yet
```

Root cause:

The Deployment Pods had only existed for a few seconds and Metrics Server had not scraped them yet.

Resolution:

Use bounded retry loops before treating missing metrics as a failure.

### Shell Termination from Transient Monitoring Errors

A strict shell using:

```bash
set -e
```

can terminate execution when a temporary command such as `kubectl top` returns non-zero.

Transient monitoring checks should instead:

- retry
- report diagnostic context
- continue safely
- avoid terminating the SSH session unnecessarily

### Probe Failures

Incorrect probe paths caused:

- readiness failure
- `Ready=false`
- `Unhealthy` events
- liveness failures
- container restart increments

These behaviors were diagnosed with:

```text
kubectl get
kubectl describe
kubectl logs
kubectl logs --previous
kubectl get events
```

## Cleanup

Remove all runtime resources:

```bash
kubectl delete namespace observability-health
```

Local manifests and captured evidence remain preserved.

## Key Skills Demonstrated

- Kubernetes health checks
- startup probes
- readiness probes
- liveness probes
- kubelet restart behavior
- readiness traffic control
- Metrics Server integration
- kubectl top
- Pod CPU monitoring
- Pod memory monitoring
- node metrics
- resource requests and limits
- restart count analysis
- Kubernetes event inspection
- current container logs
- previous container logs
- probe-failure debugging
- workload recovery validation
- Deployment rollout monitoring
- replica scaling
- aggregated logs
- label-based workload inspection
- resource constraint analysis
- eventually consistent metrics handling
- runtime evidence capture
- safe cleanup

## Real-World Use Case

These patterns are useful for production workloads that need reliable health signaling and fast operational diagnosis.

Examples include:

- API services
- AI inference endpoints
- background processing services
- internal platform components
- web applications
- microservices
- data services
- model-serving systems

Correct health checks help Kubernetes make better lifecycle and routing decisions, while metrics and debugging tools reduce time-to-diagnosis when workloads behave unexpectedly.

## Lessons Learned

- Liveness and readiness probes solve different problems and should not be treated interchangeably.
- Startup probes prevent premature failure decisions during initialization.
- Readiness failures affect traffic eligibility without necessarily restarting a container.
- Liveness failures can automatically restart unhealthy containers.
- `kubectl describe` and events are often more useful than application logs for probe failures.
- `kubectl logs --previous` is valuable after container restarts.
- Metrics Server data is eventually available rather than instantaneous.
- A healthy new Pod may temporarily have no `kubectl top` data.
- Resource limits should be observed empirically rather than assumed to cause failure.
- Deployment-level observability requires examining groups of replicas rather than one Pod in isolation.
