# Kubernetes Health Probes and Runtime Debugging

## Overview

This implementation demonstrates production-oriented Kubernetes application health management using startup, readiness, and liveness probes together with systematic runtime debugging techniques.

The environment intentionally introduces health-check failures to verify how Kubernetes changes traffic eligibility, restarts unhealthy containers, records probe events, and preserves previous container logs.

It also includes reusable diagnostic tooling for inspecting Pod conditions, restart history, probe configuration, events, current logs, and previous container instances.

## What This Demonstrates

- Readiness-based traffic gating
- Liveness-driven container recovery
- Startup probe protection for initialization
- Service endpoint changes when Pods become NotReady
- Controlled readiness and liveness failures
- Container restart verification
- Probe endpoint troubleshooting
- Pod condition analysis
- Kubernetes event analysis
- Current and previous container logs
- Timestamped and filtered log analysis
- Reusable probe debugging automation
- Production-style probe configuration

## Architecture

    Kubernetes Cluster
            |
            +--------------------------------------------------+
            |
            +--> readiness-app
            |      |
            |      +--> 2 Nginx replicas
            |      +--> readiness probe
            |      +--> Service
            |      +--> EndpointSlice traffic gating
            |
            +--> probe-demo-app
            |      |
            |      +--> startup probe
            |      +--> readiness probe
            |      +--> liveness probe
            |
            +--> python-probe-app
            |      |
            |      +--> /ready
            |      +--> /health
            |      +--> controlled marker-file failures
            |      +--> automatic restart verification
            |
            +--> debug-app
            |      |
            |      +--> intentionally invalid probe paths
            |      +--> event/condition/restart diagnosis
            |      +--> corrected health configuration
            |
            +--> logging-app
            |      |
            |      +--> HTTP probe request logging
            |      +--> timestamp analysis
            |
            +--> optimized-app
                   |
                   +--> production-style startup/readiness/liveness
                   +--> resource requests and limits

    Diagnostic Layer
            |
            +--> kubectl describe
            +--> Kubernetes Events
            +--> Pod Conditions
            +--> Container Status
            +--> kubectl logs
            +--> kubectl logs --previous
            +--> debug-probes.sh

## Probe Responsibilities

### Startup Probe

The startup probe determines whether the application has completed initialization.

While it is still failing, Kubernetes does not execute normal liveness or readiness checks against the container.

This prevents slow-starting applications from being killed prematurely.

Example:

    startupProbe:
      httpGet:
        path: /
        port: http
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 12

### Readiness Probe

The readiness probe determines whether the Pod should receive traffic.

A failing readiness probe:

- keeps the container running
- changes the Pod Ready condition to false
- removes the Pod from eligible Service endpoints
- does not restart the container

Example:

    readinessProbe:
      httpGet:
        path: /ready
        port: http
      periodSeconds: 5
      timeoutSeconds: 2
      failureThreshold: 2

### Liveness Probe

The liveness probe determines whether the running application is still healthy.

Repeated failures cause kubelet to restart the container.

Example:

    livenessProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 10
      timeoutSeconds: 2
      failureThreshold: 2

## Readiness Traffic-Gating Test

The readiness workload uses two Nginx replicas behind a ClusterIP Service.

Initial state:

    kubectl get pods -l app=readiness-app

Both replicas should show Ready.

Service endpoint readiness can be inspected with:

    kubectl get endpointslice \
      -l kubernetes.io/service-name=readiness-service

One Pod is intentionally made NotReady by removing its readiness marker:

    kubectl exec <pod-name> -- \
      rm -f /usr/share/nginx/html/ready

After the configured failure threshold:

- the Pod remains Running
- Ready becomes False
- restart count remains unchanged
- only the healthy replica remains traffic-eligible

Restore the endpoint with:

    kubectl exec <pod-name> -- \
      sh -c 'echo "ready" > /usr/share/nginx/html/ready'

The Pod becomes Ready again and returns to the endpoint set.

## Controlled Probe Failure Application

The Python workload exposes:

    /
    /ready
    /health

Readiness depends on:

    /tmp/ready

Liveness depends on:

    /tmp/healthy

Both marker files are created when the application starts.

### Trigger Readiness Failure

    kubectl exec <pod-name> -- \
      rm -f /tmp/ready

Expected result:

    Pod Ready condition -> False
    Container state     -> Running
    Restart count       -> unchanged
    /ready              -> HTTP 503

Restore:

    kubectl exec <pod-name> -- \
      touch /tmp/ready

### Trigger Liveness Failure

    kubectl exec <pod-name> -- \
      rm -f /tmp/healthy

Expected result:

    /health -> HTTP 500

After repeated failed liveness checks:

    container restart count increases

Because the container initialization recreates the health markers, the application returns to a healthy and Ready state after restart.

## Verifying Container Recovery

Inspect restart count:

    kubectl get pod <pod-name> \
      -o jsonpath='{.status.containerStatuses[0].restartCount}'

Inspect the last termination:

    kubectl get pod <pod-name> \
      -o jsonpath='{.status.containerStatuses[0].lastState}'

Inspect current status:

    kubectl get pod <pod-name> \
      -o jsonpath='{.status.containerStatuses[0].state}'

## Debugging Misconfigured Probes

An intentionally broken workload was configured with endpoints that do not exist:

    readinessProbe:
      httpGet:
        path: /also-nonexistent

    livenessProbe:
      httpGet:
        path: /nonexistent

Nginx itself was healthy, but the health checks repeatedly received HTTP failures.

This creates an important distinction:

    healthy application process
                !=
    correctly configured Kubernetes health check

## Systematic Debugging Workflow

### 1. Check Pod State

    kubectl get pod <pod-name> -o wide

Look for:

- Ready state
- Running state
- restart count
- Pod IP
- node placement

### 2. Describe the Pod

    kubectl describe pod <pod-name>

Important areas:

- Conditions
- Container Status
- Last State
- Restart Count
- Liveness probe
- Readiness probe
- Events

### 3. Inspect Events

    kubectl get events \
      --field-selector involvedObject.name=<pod-name> \
      --sort-by='.lastTimestamp'

Probe failures typically appear as events such as:

    Readiness probe failed
    Liveness probe failed
    Container failed liveness probe and will be restarted

### 4. Inspect Pod Conditions

    kubectl get pod <pod-name> \
      -o json | jq '.status.conditions'

Useful conditions include:

    Initialized
    Ready
    ContainersReady
    PodScheduled

### 5. Inspect Container Status

    kubectl get pod <pod-name> \
      -o json | jq '.status.containerStatuses'

This provides:

- ready state
- restart count
- current state
- previous termination state
- container ID
- image details

### 6. Inspect Probe Configuration

    kubectl get pod <pod-name> \
      -o json | jq '
        .spec.containers[] |
        {
          startupProbe: .startupProbe,
          readinessProbe: .readinessProbe,
          livenessProbe: .livenessProbe
        }
      '

### 7. Test the Endpoint Manually

Examples:

    kubectl exec <pod-name> -- \
      wget -S -O- http://127.0.0.1/

    kubectl exec <pod-name> -- \
      wget -S -O- http://127.0.0.1/ready

    kubectl exec <pod-name> -- \
      wget -S -O- http://127.0.0.1/health

This separates application failures from incorrect probe definitions.

## Current and Previous Logs

Current container logs:

    kubectl logs <pod-name>

Recent lines:

    kubectl logs <pod-name> --tail=50

Timestamped logs:

    kubectl logs <pod-name> \
      --timestamps=true

Previous container instance:

    kubectl logs <pod-name> \
      --previous

The `--previous` option is particularly useful after liveness-triggered restarts because the current container may already be healthy again.

## Probe Request Logging

The logging workload sends Nginx access logs to stdout and errors to stderr.

Probe requests can therefore be observed directly.

Filter readiness checks:

    kubectl logs <pod-name> | \
      grep 'GET /ready'

Filter liveness checks:

    kubectl logs <pod-name> | \
      grep 'GET /health'

Look for HTTP errors:

    kubectl logs <pod-name> | \
      grep -E '" (4|5)[0-9][0-9] '

This makes probe timing and HTTP status behavior visible through normal container logging.

## Reusable Debugging Tool

The included script:

    debug-probes.sh

collects a complete health/debugging snapshot for a Pod.

Usage:

    ./debug-probes.sh <pod-name>

Optional namespace:

    ./debug-probes.sh <pod-name> <namespace>

It reports:

- Pod status
- conditions
- container status
- startup probe configuration
- readiness probe configuration
- liveness probe configuration
- recent Kubernetes events
- current logs from every container
- previous logs when available
- restart history
- current and previous container states

Example:

    ./debug-probes.sh my-app-pod

## Production-Oriented Probe Pattern

A representative configuration:

    startupProbe:
      httpGet:
        path: /
        port: http
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 12

    readinessProbe:
      httpGet:
        path: /
        port: http
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 3
      successThreshold: 1

    livenessProbe:
      httpGet:
        path: /
        port: http
      periodSeconds: 30
      timeoutSeconds: 5
      failureThreshold: 3

This gives startup up to approximately 60 seconds before normal health evaluation while keeping readiness relatively responsive and liveness more conservative.

## Probe Design Guidance

### Keep Readiness Sensitive to Traffic Eligibility

Readiness should answer:

    Can this application successfully handle new traffic right now?

Failures should remove the Pod from traffic without killing the process.

### Keep Liveness Focused on Process Recovery

Liveness should answer:

    Is the application stuck or unhealthy enough that restarting it is useful?

Do not make liveness depend unnecessarily on remote databases or external APIs.

An external dependency outage should not usually cause every application container to restart continuously.

### Use Startup Probes for Slow Initialization

Startup probes are appropriate for applications that:

- load large models
- perform migrations
- hydrate caches
- initialize JVM runtimes
- restore state
- perform expensive startup work

### Avoid Aggressive Thresholds

Very short timeouts or failure thresholds can cause restart loops during temporary latency spikes.

Probe configuration should reflect realistic application behavior.

## Resource Configuration

The workloads also define resource requests and limits.

Example:

    resources:
      requests:
        memory: 32Mi
        cpu: 25m
      limits:
        memory: 128Mi
        cpu: 100m

Probe reliability can be affected by severe CPU starvation or memory pressure, so health-check design should be considered together with resource configuration.

## Common Failure Scenarios

### Pod Stuck NotReady

Check:

    kubectl get pod <pod-name>

    kubectl describe pod <pod-name>

    kubectl get events \
      --field-selector involvedObject.name=<pod-name>

Then manually test the readiness endpoint.

### Container Keeps Restarting

Check:

    kubectl get pod <pod-name> \
      -o jsonpath='{.status.containerStatuses[0].restartCount}'

    kubectl get pod <pod-name> \
      -o jsonpath='{.status.containerStatuses[0].lastState}'

    kubectl logs <pod-name> --previous

Frequent restarts combined with liveness failures commonly indicate:

- incorrect probe path
- incorrect port
- application deadlock
- dependency on unavailable local state
- overly aggressive timing
- application startup slower than expected

### Probe Timeout

Manually test the endpoint and compare response time against `timeoutSeconds`.

A consistently slow endpoint may require:

- application optimization
- a more appropriate health endpoint
- corrected resource allocation
- carefully adjusted timeout values

Increasing timeout blindly should not replace investigating the underlying latency.

## Files

    readiness-probe-app.yaml
    probe-demo-config.yaml
    liveness-readiness-app.yaml
    python-probe-app.yaml
    debug-app.yaml
    debug-app-fixed.yaml
    logging-app.yaml
    optimized-app.yaml
    final-test-app.yaml
    debug-probes.sh
    debug-probe-evidence.txt
    python-probe-debug-report.txt
    logging-probe-debug-report.txt
    optimized-probe-debug-report.txt
    final-probe-debug-report.txt
    probe-log-analysis.txt
    probe-validation-summary.txt
    probe-events.txt

## Tools and Technologies

- Kubernetes
- K3s
- kubectl
- Nginx
- Python
- HTTP health endpoints
- Startup probes
- Readiness probes
- Liveness probes
- ClusterIP Services
- EndpointSlice
- Kubernetes Events
- Pod Conditions
- Container restart history
- Bash
- jq

## Skills Demonstrated

- Kubernetes health-check architecture
- Startup probe configuration
- Readiness-based traffic control
- Liveness-based self-healing
- Controlled failure simulation
- Kubernetes Service endpoint analysis
- Pod condition inspection
- Container restart diagnosis
- Event-driven troubleshooting
- Current and previous log analysis
- HTTP health endpoint debugging
- Root-cause analysis of misconfigured probes
- Production probe tuning
- Reusable operational tooling

## Real-World Use Case

These patterns apply directly to production workloads where Kubernetes must distinguish between:

- applications that are still starting
- applications that are running but temporarily unable to serve traffic
- applications that are unhealthy and require restart

Correctly separating those states prevents unnecessary restarts, reduces failed requests during initialization or temporary degradation, and improves workload self-healing behavior.

The debugging workflow also provides platform and SRE teams with a repeatable method for investigating health-check incidents rather than guessing from Pod status alone.

## Key Lessons

- Readiness controls traffic, not process lifecycle.
- Liveness controls recovery through container restart.
- Startup probes protect initialization from premature health enforcement.
- A Running Pod is not necessarily Ready.
- A healthy application can still fail because its probe path is wrong.
- Kubernetes events frequently expose the fastest path to probe-related root causes.
- Previous-container logs are critical after automatic restarts.
- Manual endpoint testing helps separate probe misconfiguration from actual application failure.
- Probe timing should be based on application behavior rather than arbitrary defaults.
- Health checks should be observable and easy to troubleshoot.
