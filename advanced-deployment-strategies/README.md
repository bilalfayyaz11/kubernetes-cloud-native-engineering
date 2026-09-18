# Kubernetes Advanced Deployment Strategies

## What This Does

This implementation demonstrates production-oriented Kubernetes release strategies using Deployments, Services, ConfigMaps, EndpointSlices, health checks, rollout history, rollback automation, and traffic validation.

It covers three release stages:

- Stable baseline deployment
- Blue/green deployment with production Service cutover
- Canary deployment using replica-ratio exposure

The workflow also validates application responses, observes backend transitions, captures deployment metrics, records runtime evidence, and performs clean resource teardown.

## Architecture

```text
                         +----------------------+
                         |  Production Service  |
                         | sample-app-service   |
                         +----------+-----------+
                                    |
                    +---------------+---------------+
                    |                               |
                    v                               v
             +-------------+                 +-------------+
             |     v1      |                 |     v2      |
             |    Blue     |                 |    Green    |
             | 3 replicas  |                 | 3 replicas  |
             +-------------+                 +-------------+

                  BLUE/GREEN CUTOVER
      Service selector changes between v1 and v2


                         +----------------------+
                         |  Production Service  |
                         | selector: app only   |
                         +----------+-----------+
                                    |
                       +------------+------------+
                       |                         |
                       v                         v
                +-------------+           +-------------+
                |     v1      |           |     v3      |
                |   Stable    |           |   Canary    |
                +-------------+           +-------------+

                 CANARY EXPOSURE STAGES

             9 x v1  + 1 x v3
             3 x v1  + 1 x v3
             2 x v1  + 2 x v3

                Final promotion:

             0 x v1  + 3 x v3
```

## Repository Structure

```text
advanced-deployment-strategies/
├── README.md
├── app-deployment-v1.yaml
├── app-deployment-v2.yaml
├── app-deployment-v3.yaml
├── app-service.yaml
├── blue-green-services.yaml
├── rollback-to-blue.sh
├── monitor-canary.sh
├── complete-canary-rollout.sh
├── rollback-canary.sh
├── deployment-health-check.sh
├── cleanup.sh
└── evidence/
    ├── deployments.txt
    ├── pods.txt
    ├── services.txt
    ├── production-endpointslice.yaml
    ├── node-metrics.txt
    ├── pod-container-metrics.txt
    ├── events.txt
    ├── rollout-history.txt
    ├── sample-app-v1-final.yaml
    ├── sample-app-v2-final.yaml
    ├── sample-app-v3-final.yaml
    ├── sample-app-service-final.yaml
    ├── final-v3-response.html
    └── deployment-health-check.txt
```

## Prerequisites

- Ubuntu Linux
- Docker Engine
- kubectl
- Minikube
- curl
- jq
- sudo access

## Environment Setup

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

Start Kubernetes:

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

## Baseline Deployment

The first release deploys version 1 with:

- 3 replicas
- ConfigMap-backed HTML content
- readiness probe
- liveness probe
- CPU and memory requests
- CPU and memory limits
- ClusterIP production Service

Apply:

```bash
kubectl apply -f app-deployment-v1.yaml
kubectl apply -f app-service.yaml
```

Verify rollout:

```bash
kubectl rollout status \
  deployment/sample-app-v1 \
  -n deployment-strategies
```

Verify Pods:

```bash
kubectl get pods \
  -n deployment-strategies \
  -l app=sample-app,version=v1
```

## Blue/Green Deployment

The second release runs version 2 beside version 1 instead of immediately replacing the stable environment.

Deploy Green:

```bash
kubectl apply -f app-deployment-v2.yaml
kubectl apply -f blue-green-services.yaml
```

Verify both releases:

```bash
kubectl get deployments \
  -n deployment-strategies \
  -l app=sample-app
```

```bash
kubectl get pods \
  -n deployment-strategies \
  -l app=sample-app \
  --show-labels
```

## Isolated Blue and Green Validation

Blue:

```bash
kubectl port-forward \
  service/sample-app-blue \
  8081:80 \
  -n deployment-strategies
```

Expected content:

```text
Version 1.0 - Blue Environment
```

Green:

```bash
kubectl port-forward \
  service/sample-app-green \
  8082:80 \
  -n deployment-strategies
```

Expected content:

```text
Version 2.0 - Green Environment
```

## Production Cutover

Switch production from Blue to Green:

```bash
kubectl patch service sample-app-service \
  -n deployment-strategies \
  -p '{"spec":{"selector":{"app":"sample-app","version":"v2"}}}'
```

Verify selector:

```bash
kubectl get service sample-app-service \
  -n deployment-strategies \
  -o jsonpath='{.spec.selector}{"\n"}'
```

## EndpointSlice Validation

Modern Kubernetes versions use EndpointSlice for Service backend discovery.

Inspect production backends:

```bash
kubectl get endpointslice \
  -n deployment-strategies \
  -l kubernetes.io/service-name=sample-app-service \
  -o wide
```

This confirms which Pod IPs currently receive production traffic.

## Important Port-Forward Behavior

A `kubectl port-forward service/...` connection resolves to a backing Pod when the forwarding session starts.

If the Service selector changes afterward, an already-running port-forward can continue targeting the Pod selected earlier.

Correct validation pattern:

```text
Start port-forward
Verify current release
Stop port-forward

Change Service selector
Wait for EndpointSlice update

Start new port-forward
Verify new release
```

This behavior was explicitly accounted for during blue/green validation.

## Blue Rollback

Rollback automation:

```bash
./rollback-to-blue.sh
```

Equivalent selector change:

```bash
kubectl patch service sample-app-service \
  -n deployment-strategies \
  -p '{"spec":{"selector":{"app":"sample-app","version":"v1"}}}'
```

A fresh port-forward is then created to verify that version 1 is serving production traffic again.

## Canary Deployment

Version 3 is introduced as a canary release.

Deploy:

```bash
kubectl apply -f app-deployment-v3.yaml
```

Verify:

```bash
kubectl rollout status \
  deployment/sample-app-v3 \
  -n deployment-strategies
```

## Shared Production Service

For the canary stage, the version selector is removed so the production Service can route to both stable and canary Pods sharing:

```text
app=sample-app
```

The Service therefore discovers both versions through EndpointSlices.

## Canary Exposure

### Stage 1

```text
Stable v1: 9 replicas
Canary v3: 1 replica
```

Commands:

```bash
kubectl scale deployment sample-app-v1 \
  -n deployment-strategies \
  --replicas=9

kubectl scale deployment sample-app-v3 \
  -n deployment-strategies \
  --replicas=1
```

### Stage 2

```text
Stable v1: 3 replicas
Canary v3: 1 replica
```

### Stage 3

```text
Stable v1: 2 replicas
Canary v3: 2 replicas
```

## Replica Ratios vs Weighted Traffic

Replica counts can influence the number of backend endpoints available to a Kubernetes Service, but they do not provide deterministic weighted routing.

For example:

```text
9 stable replicas
1 canary replica
```

creates an endpoint population resembling a 90/10 ratio, but this does not guarantee exactly 90% and 10% of HTTP requests.

For precise weighted traffic control, a component with explicit traffic weighting would normally be introduced, such as:

- Gateway API implementation
- ingress controller with traffic weighting
- service mesh
- dedicated progressive delivery controller

## Traffic Observation

Traffic sampling is handled by:

```bash
./monitor-canary.sh
```

The script records:

- v1 responses
- v3 responses
- failed responses
- unexpected responses
- observed percentage distribution

The observed result is treated as runtime evidence rather than assuming replica count equals exact traffic percentage.

## Canary Promotion

Promote v3:

```bash
./complete-canary-rollout.sh
```

The workflow:

1. scales v3 to 3 replicas
2. waits for successful rollout
3. scales v1 to 0

Final desired state:

```text
v1 = 0
v3 = 3
```

## Canary Rollback

Rollback automation:

```bash
./rollback-canary.sh
```

The rollback:

1. restores v1 to 3 replicas
2. waits for v1 readiness
3. scales v3 to 0
4. validates the stable response

After rollback validation, v3 can be promoted again.

## Metrics Server

Enable metrics:

```bash
minikube addons enable metrics-server
```

Verify:

```bash
kubectl top nodes
```

Container-level metrics:

```bash
kubectl top pods \
  -n deployment-strategies \
  -l app=sample-app \
  --containers
```

## Deployment Health Monitoring

Run:

```bash
./deployment-health-check.sh
```

The health check reports:

- Deployment status
- Pod state
- Services
- production selector
- EndpointSlices
- recent events
- resource usage
- rollout history
- deployment conditions

## Rollout History

Version 1:

```bash
kubectl rollout history \
  deployment/sample-app-v1 \
  -n deployment-strategies
```

Version 2:

```bash
kubectl rollout history \
  deployment/sample-app-v2 \
  -n deployment-strategies
```

Version 3:

```bash
kubectl rollout history \
  deployment/sample-app-v3 \
  -n deployment-strategies
```

## Troubleshooting Commands

Inspect a Deployment:

```bash
kubectl describe deployment sample-app-v3 \
  -n deployment-strategies
```

Inspect Pods:

```bash
kubectl get pods \
  -n deployment-strategies \
  -l app=sample-app \
  -o wide
```

Inspect application logs:

```bash
kubectl logs \
  -n deployment-strategies \
  -l app=sample-app,version=v3
```

Inspect Service configuration:

```bash
kubectl describe service sample-app-service \
  -n deployment-strategies
```

Inspect EndpointSlices:

```bash
kubectl get endpointslice \
  -n deployment-strategies \
  -l kubernetes.io/service-name=sample-app-service \
  -o yaml
```

Inspect events:

```bash
kubectl get events \
  -n deployment-strategies \
  --sort-by='.metadata.creationTimestamp'
```

## Evidence Capture

Runtime validation is preserved under:

```text
evidence/
```

The captured evidence includes:

- final Deployment state
- Pod state
- Service configuration
- EndpointSlice data
- node metrics
- container metrics
- Kubernetes events
- rollout history
- final live resource YAML
- final v3 HTML response
- health-check output

This preserves operational proof even after Kubernetes resources are removed.

## Cleanup

Run:

```bash
./cleanup.sh
```

The cleanup removes the Kubernetes namespace and all contained resources while preserving local manifests, scripts, and evidence.

## Key Skills Demonstrated

- Kubernetes Deployment design
- Deployment replica management
- RollingUpdate configuration
- ConfigMap-backed application releases
- readiness and liveness probes
- resource requests and limits
- ClusterIP Service design
- blue/green release strategy
- production Service cutover
- rollback automation
- EndpointSlice inspection
- canary rollout design
- progressive exposure
- request distribution sampling
- application response verification
- release promotion
- release rollback
- Metrics Server integration
- per-container resource monitoring
- rollout history inspection
- Kubernetes event analysis
- deployment troubleshooting
- runtime evidence capture
- clean resource teardown

## Real-World Use Case

These release patterns help reduce production risk when introducing new versions.

Blue/green is useful when two complete application versions can run simultaneously and production traffic needs to switch quickly between them.

Canary releases are useful when a new version should be exposed gradually so operational behavior can be observed before full promotion.

The same concepts apply to API platforms, microservices, AI inference services, internal developer platforms, customer-facing SaaS systems, and continuous delivery pipelines.

## Lessons Learned

- Release validation must verify actual application behavior, not only Kubernetes resource state.
- Blue/green cutover is fundamentally a Service routing decision when both environments already exist.
- EndpointSlice provides modern visibility into the Pods behind a Service.
- An existing Service port-forward should not be used to prove a selector transition.
- Fresh network validation is required after switching Service backends.
- Replica ratios approximate canary exposure but do not guarantee weighted traffic percentages.
- Progressive delivery needs measurable health checks before promotion.
- Rollback procedures should be executable rather than documented only conceptually.
- Runtime evidence should be captured before resource cleanup.
- Resource metrics and rollout history substantially improve deployment troubleshooting.
