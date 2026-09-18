# Kubernetes Runtime Debugging

## Overview

This implementation demonstrates production-style Kubernetes debugging using multiple troubleshooting techniques, including:

- Kubernetes events
- `kubectl describe`
- `kubectl logs`
- `kubectl logs --previous`
- `kubectl exec`
- ephemeral containers
- `kubectl debug --target`
- network debugging
- process inspection
- filesystem inspection
- multi-container Pod debugging
- image-pull failure diagnosis
- scheduling failure diagnosis
- resource constraint analysis
- runtime evidence capture

The goal is to diagnose Kubernetes workloads without unnecessarily modifying or rebuilding application containers.

## Architecture

```text
                       +---------------------------+
                       |      Kubernetes Pod       |
                       +-------------+-------------+
                                     |
                 +-------------------+-------------------+
                 |                                       |
                 v                                       v
       +---------------------+                 +---------------------+
       | Application         |                 | Ephemeral Debugger  |
       | Container           |                 | Container           |
       +---------------------+                 +---------------------+
       | Minimal runtime     |                 | Diagnostic tooling  |
       | App process         |                 | ps / ip / ss        |
       | Limited utilities   |                 | DNS / curl / trace  |
       +---------------------+                 +---------------------+
                 |                                       |
                 +-------------------+-------------------+
                                     |
                                     v
                         Shared Pod namespaces
```

## Repository Structure

```text
kubernetes-runtime-debugging/
├── README.md
├── broken-app.yaml
├── working-app.yaml
├── problematic-app.yaml
├── complex-app.yaml
├── wrong-image.yaml
├── resource-issue.yaml
├── network-test.yaml
├── debugging-comparison.md
├── debugging-best-practices.md
└── evidence/
    ├── broken-app-describe.txt
    ├── broken-app-events.txt
    ├── broken-app-state.yaml
    ├── broken-app-configmap-recovery.txt
    ├── working-app-describe.txt
    ├── working-app-state.yaml
    ├── working-app-environment.txt
    ├── working-app-root-filesystem.txt
    ├── working-app-volume.txt
    ├── working-app-df.txt
    ├── working-app-nginx-config.txt
    ├── working-app-processes.txt
    ├── working-app-network.txt
    ├── working-app-memory.txt
    ├── working-app-kubectl.log
    ├── nginx-log-targets.txt
    ├── working-app-access-via-kubectl.log
    ├── container-logging-model.txt
    ├── working-app-shell-tools.txt
    ├── tool-gap-summary.txt
    ├── problematic-app-before-debug.log
    ├── problematic-app-tool-gaps.txt
    ├── ephemeral-containers-before.json
    ├── ephemeral-containers-after.json
    ├── ephemeral-container-status.json
    ├── ephemeral-tool-inventory.txt
    ├── ephemeral-processes.txt
    ├── ephemeral-network-interfaces.txt
    ├── ephemeral-routing.txt
    ├── ephemeral-sockets.txt
    ├── ephemeral-dns.txt
    ├── kubernetes-service-connectivity.txt
    ├── target-process-environment.txt
    ├── target-root-filesystem.txt
    ├── problematic-app-with-ephemeral.yaml
    ├── problematic-app-with-ephemeral-describe.txt
    ├── complex-app-shared-data.txt
    ├── complex-app-http.txt
    ├── complex-debug-http.txt
    ├── complex-debug-ip.txt
    ├── complex-debug-sockets.txt
    ├── complex-debug-dns.txt
    ├── wrong-image-describe.txt
    ├── wrong-image-events.txt
    ├── resource-issue-describe.txt
    ├── network-dns.txt
    ├── network-route.txt
    ├── network-kubernetes-service.txt
    ├── final-pod-state.txt
    └── final-events.txt
```

## Environment

Tested with:

- Ubuntu Linux
- Docker
- Kubernetes via Minikube
- kubectl
- containerd runtime
- jq
- curl

## Namespace

All workloads were isolated inside:

```text
runtime-debugging
```

Create it with:

```bash
kubectl create namespace runtime-debugging
```

## Scenario 1 — Missing ConfigMap

The first workload intentionally references a ConfigMap that does not exist:

```yaml
volumes:
  - name: config-volume
    configMap:
      name: app-config
```

The Pod cannot start correctly until the dependency exists.

Useful commands:

```bash
kubectl get pods -n runtime-debugging

kubectl describe pod broken-app \
  -n runtime-debugging

kubectl get events \
  -n runtime-debugging \
  --field-selector involvedObject.name=broken-app
```

Typical failure indicators include:

```text
FailedMount
configmap not found
```

## Repairing the ConfigMap Dependency

The missing dependency was created with:

```bash
kubectl create configmap app-config \
  -n runtime-debugging \
  --from-literal=app.conf='server_name=debug-app'
```

The Pod was then recreated and successfully mounted:

```text
/etc/config/app.conf
```

This demonstrated the difference between diagnosing the root cause and simply restarting a workload.

## Healthy Comparison Pod

A healthy Nginx workload was deployed for comparison.

It included:

- environment variables
- an `emptyDir` volume
- resource requests and limits

Example inspection:

```bash
kubectl exec working-app \
  -n runtime-debugging \
  -- printenv SERVER_NAME
```

## kubectl exec

`kubectl exec` is useful for fast investigation of a running application container.

Examples:

```bash
kubectl exec working-app \
  -n runtime-debugging \
  -- pwd
```

```bash
kubectl exec working-app \
  -n runtime-debugging \
  -- ls -la /
```

```bash
kubectl exec working-app \
  -n runtime-debugging \
  -- df -h
```

## Application Tool Availability

One important observation was that application images do not necessarily include every diagnostic utility.

The application container was checked for:

```text
sh
bash
ps
ss
netstat
ip
curl
wget
free
tcpdump
strace
```

Some tools were available while others were absent.

This demonstrates why production application images should not be assumed to contain full debugging toolkits.

## Container Logging Model

The Nginx image exposed:

```text
/var/log/nginx/access.log -> /dev/stdout
/var/log/nginx/error.log  -> /dev/stderr
```

Therefore, the correct Kubernetes-native log inspection method is:

```bash
kubectl logs working-app \
  -n runtime-debugging
```

Directly treating these symlinks like traditional persistent log files can block or behave unexpectedly.

## kubectl logs

Application logs were inspected with:

```bash
kubectl logs working-app \
  -n runtime-debugging \
  --timestamps
```

For restarted containers, use:

```bash
kubectl logs POD_NAME \
  -n runtime-debugging \
  --previous
```

## Why Ephemeral Containers Matter

Minimal application images may lack:

- packet capture tools
- DNS utilities
- process inspection tools
- network utilities
- tracing tools

Instead of modifying the application image, a dedicated ephemeral container can be attached to the running Pod.

This keeps troubleshooting tooling separate from the workload.

## Creating an Ephemeral Container

Example:

```bash
kubectl debug problematic-app \
  -n runtime-debugging \
  --image=nicolaka/netshoot:latest \
  --target=app-container \
  --container=runtime-debugger \
  --attach=false \
  -- sleep 3600
```

The debugger is added through the Pod ephemeral-container subresource.

## Inspecting Ephemeral Containers

```bash
kubectl get pod problematic-app \
  -n runtime-debugging \
  -o json \
  | jq '.spec.ephemeralContainers'
```

Runtime status:

```bash
kubectl get pod problematic-app \
  -n runtime-debugging \
  -o json \
  | jq '.status.ephemeralContainerStatuses'
```

## Debugging Tools

The dedicated debugger provided tools suitable for deeper troubleshooting, including utilities for:

- processes
- networking
- DNS
- routes
- sockets
- packet capture
- tracing

Example:

```bash
kubectl exec problematic-app \
  -n runtime-debugging \
  -c runtime-debugger \
  -- ps aux
```

## Process Inspection

Using `--target` allows the debugger to target the application container.

Process inspection:

```bash
kubectl exec problematic-app \
  -n runtime-debugging \
  -c runtime-debugger \
  -- ps aux
```

Where supported by the runtime, target-container processes can be inspected through the debugger.

## Process Environment

When a target PID is visible:

```bash
tr '\0' '\n' < /proc/<PID>/environ
```

This can expose runtime environment variables for diagnosis.

Process environments may contain sensitive information and should not be committed blindly to source control.

## Target Filesystem Inspection

The target container filesystem can be inspected through procfs where namespace visibility permits:

```bash
ls -la /proc/<PID>/root
```

This is useful when the target application image lacks its own troubleshooting utilities.

## Network Inspection

The ephemeral debugger was used for:

```bash
ip addr show
```

```bash
ip route
```

```bash
ss -tulpn
```

```bash
nslookup kubernetes.default.svc.cluster.local
```

This allows investigation of Pod networking without adding tools to the application container.

## Kubernetes API Connectivity

Cluster service connectivity can be tested with:

```bash
curl -kIs https://kubernetes.default.svc
```

This verifies DNS resolution and connectivity to the Kubernetes service from inside the Pod network namespace.

## Multi-Container Debugging

A Pod with two application containers was deployed:

```text
web-app
data-processor
```

Both containers shared an `emptyDir` volume.

The data processor continuously generated:

```text
/shared/index.html
```

while Nginx served the same file through:

```text
/usr/share/nginx/html
```

This demonstrated:

- shared Pod storage
- multi-container behavior
- cross-container data flow
- debugger targeting of a specific container

## Shared Volume Validation

Data written by:

```text
data-processor
```

was successfully served by:

```text
web-app
```

through their shared volume.

## Debugging a Multi-Container Pod

The debugger targeted the web container:

```bash
kubectl debug complex-app \
  -n runtime-debugging \
  --image=nicolaka/netshoot:latest \
  --target=web-app \
  --container=complex-debugger \
  --attach=false \
  -- sleep 3600
```

Network, DNS, and HTTP behavior were then inspected without modifying either application container.

## ImagePull Failure Scenario

An intentionally invalid image was deployed:

```yaml
image: nonexistent-image-example-xyz:latest
```

The failure was diagnosed using:

```bash
kubectl describe pod wrong-image-pod \
  -n runtime-debugging
```

and:

```bash
kubectl get events \
  -n runtime-debugging
```

Expected symptoms included:

```text
ErrImagePull
ImagePullBackOff
```

This is an image acquisition failure, not a scheduling failure.

## Scheduling Failure Scenario

A Pod requested more resources than the node could provide:

```yaml
resources:
  requests:
    memory: "10Gi"
    cpu: "8"
```

The Pod remained unscheduled.

Useful command:

```bash
kubectl describe pod resource-issue-pod \
  -n runtime-debugging
```

Expected scheduling indication:

```text
Unschedulable
```

Typical causes include:

```text
Insufficient cpu
Insufficient memory
```

## Failure Classification

The scenarios demonstrate the importance of distinguishing different failure classes.

### Image Failure

```text
ErrImagePull
ImagePullBackOff
```

Investigate:

```text
image name
registry
tag
pull credentials
network access
```

### Scheduling Failure

```text
Pending
Unschedulable
```

Investigate:

```text
resource requests
node capacity
taints
affinity
selectors
```

### Volume / Config Failure

Examples:

```text
FailedMount
missing ConfigMap
missing Secret
```

Investigate:

```text
Pod specification
volume definitions
referenced resources
events
```

## Network Debugging

A minimal network workload was deployed and supplemented with an ephemeral network debugger.

Tests included:

```bash
nslookup kubernetes.default.svc.cluster.local
```

```bash
ip route
```

```bash
curl -kIs https://kubernetes.default.svc
```

This demonstrates debugging a minimal runtime without rebuilding it with additional networking tools.

## Debugging Method Selection

### kubectl logs

Best for:

- application output
- runtime errors
- crashes
- previous container logs

Limitation:

Only contains information emitted by the application.

### kubectl describe

Best for:

- scheduling problems
- image pulls
- volume failures
- probe failures
- Kubernetes events

Limitation:

Does not deeply inspect application runtime state.

### kubectl exec

Best for:

- environment inspection
- configuration validation
- filesystem inspection
- simple runtime checks

Limitation:

Depends on utilities available in the application image.

### Ephemeral Containers

Best for:

- minimal images
- network debugging
- process inspection
- production-style troubleshooting
- multi-container Pods

Advantages:

- dedicated troubleshooting toolkit
- no application image rebuild
- debugger remains separate from normal application containers

## Ephemeral Container Lifecycle

Ephemeral containers are intended for troubleshooting rather than normal workload functionality.

They cannot be individually removed from an existing Pod after being added.

To completely remove the debugging container, recreate or delete the Pod.

## Security Considerations

Ephemeral debugging is powerful and should be controlled carefully.

Recommended practices:

- restrict access to `pods/ephemeralcontainers`
- use least-privilege RBAC
- audit debug activity
- use trusted debugger images
- avoid exposing secrets through process environments
- treat packet captures as sensitive
- avoid committing credentials to Git
- avoid unnecessary debugging tools in production application images

## Troubleshooting Order

A useful progression is:

```text
kubectl get
    |
    v
kubectl describe
    |
    v
kubectl logs
    |
    v
kubectl logs --previous
    |
    v
kubectl exec
    |
    v
ephemeral container
    |
    v
copy/debug Pod if required
```

Start with the least intrusive diagnostic method.

## Evidence Capture

Runtime evidence was stored under:

```text
evidence/
```

Examples include:

- events
- Pod states
- Pod descriptions
- logs
- network state
- route information
- DNS output
- debugger specifications
- process inspection
- failure evidence

Evidence was captured before deleting Kubernetes resources.

## Cleanup

The complete namespace can be removed with:

```bash
kubectl delete namespace runtime-debugging
```

This removes all runtime workloads while keeping the local troubleshooting manifests and evidence.

## Key Skills Demonstrated

- Kubernetes troubleshooting
- ephemeral containers
- kubectl debug
- kubectl exec
- kubectl logs
- kubectl describe
- Kubernetes events
- ConfigMap failure diagnosis
- volume troubleshooting
- container filesystem inspection
- process namespace inspection
- network namespace debugging
- DNS troubleshooting
- routing inspection
- socket inspection
- container-native logging
- multi-container Pod debugging
- shared-volume troubleshooting
- image-pull failure diagnosis
- resource scheduling failure diagnosis
- minimal-image debugging
- runtime evidence capture
- RBAC awareness
- secure production debugging

## Real-World Use Cases

These techniques are useful when troubleshooting:

- production APIs
- AI inference services
- model-serving containers
- microservices
- minimal container images
- internal platform components
- distributed systems
- Kubernetes networking problems
- startup and configuration failures
- resource scheduling problems

## Lessons Learned

- Not every failing Pod has the same root cause.
- Kubernetes events often reveal failures faster than application logs.
- `kubectl describe` is especially valuable for Kubernetes-level problems.
- Application containers should not be expected to contain complete troubleshooting toolkits.
- `kubectl exec` is limited by the contents of the target image.
- Ephemeral containers allow powerful diagnostics without rebuilding the application.
- `kubectl debug --target` can provide visibility into the target workload while keeping the debugger separate.
- Container logs are commonly routed to stdout and stderr rather than traditional files.
- Image pull errors and resource scheduling failures require different debugging approaches.
- Process environments and packet-level diagnostics can contain sensitive data.
- Ephemeral containers cannot be individually removed after creation.
- Debugging evidence should be captured before workload cleanup.
