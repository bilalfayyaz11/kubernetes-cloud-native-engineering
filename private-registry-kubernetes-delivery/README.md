# Secure Private Registry Delivery on Kubernetes

## What This Does

This implementation demonstrates a secure container image lifecycle from application source to a running Kubernetes workload. Static application assets are built in a dedicated Node.js stage and transferred into a hardened non-root Nginx runtime, keeping build tooling and development dependencies out of the production image.

The resulting image is stored in a private Harbor registry, scanned with Trivy, authenticated from Kubernetes through an image pull secret, and deployed as a replicated workload. The runtime includes readiness and liveness probes, CPU and memory controls, restricted Linux capabilities, rolling updates, resource monitoring, load validation, and Ingress-based traffic routing.

The design reflects a production-oriented delivery pattern where container images are built once, stored centrally, scanned before use, and deployed through controlled Kubernetes mechanisms.

## Architecture

```text
+-----------------------------------------------------------+
|                    APPLICATION SOURCE                     |
|                                                           |
|  HTML + JavaScript + Build Script + Package Manifest      |
+------------------------------+----------------------------+
                               |
                               v
+-----------------------------------------------------------+
|                  MULTI-STAGE IMAGE BUILD                  |
|                                                           |
|  Stage 1: Node.js Builder                                 |
|     - Installs build dependencies                         |
|     - Minifies JavaScript                                 |
|     - Produces static distribution assets                 |
|                                                           |
|  Stage 2: Nginx Runtime                                   |
|     - UID 1001                                            |
|     - Port 8080                                           |
|     - Health endpoint                                     |
|     - No Node.js runtime                                  |
+------------------------------+----------------------------+
                               |
                               v
+-----------------------------------------------------------+
|                    PRIVATE REGISTRY                       |
|                                                           |
|  Harbor                                                   |
|     - Private image storage                               |
|     - Versioned tags                                      |
|     - Authenticated push and pull                         |
|     - Trivy vulnerability scanning                        |
+------------------------------+----------------------------+
                               |
                     Kubernetes Pull Secret
                               |
                               v
+-----------------------------------------------------------+
|                    KUBERNETES CLUSTER                     |
|                                                           |
|  Namespace: container-platform                            |
|                                                           |
|  Deployment                                               |
|  +-------------+  +-------------+  +-------------+        |
|  |    Pod 1    |  |    Pod 2    |  |    Pod 3    |        |
|  | UID 1001    |  | UID 1001    |  | UID 1001    |        |
|  +-------------+  +-------------+  +-------------+        |
|                                                           |
|  - Readiness probes                                       |
|  - Liveness probes                                        |
|  - CPU and memory requests/limits                         |
|  - Privilege escalation disabled                         |
|  - Linux capabilities dropped                            |
|                                                           |
|                    ClusterIP Service                      |
|                           |                               |
|                           v                               |
|                    Nginx Ingress                          |
+------------------------------+----------------------------+
                               |
                               v
+-----------------------------------------------------------+
|                 OBSERVABILITY & OPERATIONS                |
|                                                           |
|  Metrics Server                                           |
|  kubectl top                                              |
|  Internal traffic generation                              |
|  Rolling deployment updates                              |
|  Harbor / Trivy vulnerability results                    |
+-----------------------------------------------------------+
```

## Prerequisites

- Ubuntu Linux
- Docker Engine
- Docker Compose V2
- kubectl
- Minikube
- Harbor
- Trivy integration
- curl
- jq
- Python 3
- OpenSSL
- sudo access
- Internet connectivity

## Repository Structure

```text
private-registry-kubernetes-delivery/
├── README.md
├── webapp-deployment.yaml
├── webapp-ingress.yaml
├── webapp/
│   ├── Dockerfile
│   ├── Dockerfile.multistage
│   ├── index.html
│   ├── nginx.conf
│   ├── nginx-main.conf
│   ├── nginx-nonroot.conf
│   ├── package.json
│   ├── build.js
│   ├── update-app.sh
│   └── public/
│       ├── index.html
│       └── app.js
└── evidence/
    ├── deployment-final.yaml
    ├── service-final.yaml
    ├── ingress-final.yaml
    ├── pod-status.txt
    ├── pod-metrics.txt
    └── vulnerability-scan-v1.0.json
```

## Setup & Installation

### Install Minikube

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

### Prepare Harbor with Trivy

Install Harbor with its vulnerability scanner enabled:

```bash
sudo ./install.sh --with-trivy
```

For an isolated HTTP-based registry, Docker must explicitly trust the registry endpoint:

```json
{
  "insecure-registries": [
    "REGISTRY_HOST"
  ]
}
```

Restart Docker after modifying the daemon configuration:

```bash
sudo systemctl restart docker
```

## How to Reproduce

### 1. Build the basic image

```bash
cd webapp

docker build \
  -t webapp-basic:v1.0 \
  -f Dockerfile \
  .
```

### 2. Build the hardened multi-stage image

```bash
docker build \
  -t webapp-optimized:v1.0 \
  -f Dockerfile.multistage \
  .
```

### 3. Verify build/runtime separation

Confirm Node.js is absent from the final runtime image:

```bash
docker run --rm \
  --entrypoint sh \
  webapp-optimized:v1.0 \
  -c 'command -v node || true'
```

The command should return no Node.js binary.

Verify the runtime identity:

```bash
docker run --rm \
  --entrypoint id \
  webapp-optimized:v1.0 \
  -u
```

Expected result:

```text
1001
```

### 4. Validate the container locally

```bash
docker run -d \
  --name webapp-test \
  -p 8081:8080 \
  webapp-optimized:v1.0
```

Test the application:

```bash
curl http://localhost:8081/
```

Test the health endpoint:

```bash
curl http://localhost:8081/health
```

Expected health result:

```text
healthy
```

Remove the temporary container:

```bash
docker rm -f webapp-test
```

### 5. Authenticate with Harbor

Define the registry address and authenticate:

```bash
export HARBOR_HOST="REGISTRY_HOST"

echo "$HARBOR_PASSWORD" \
  | docker login "$HARBOR_HOST" \
      --username admin \
      --password-stdin
```

### 6. Tag and push the image

```bash
docker tag \
  webapp-optimized:v1.0 \
  "$HARBOR_HOST/platform-images/webapp:v1.0"

docker push \
  "$HARBOR_HOST/platform-images/webapp:v1.0"
```

A second tag can be published when required:

```bash
docker tag \
  webapp-optimized:v1.0 \
  "$HARBOR_HOST/platform-images/webapp:latest"

docker push \
  "$HARBOR_HOST/platform-images/webapp:latest"
```

### 7. Start Minikube with private-registry access

```bash
minikube start \
  --driver=docker \
  --container-runtime=containerd \
  --cpus=2 \
  --memory=1800mb \
  --insecure-registry="host.minikube.internal:80"
```

Verify cluster health:

```bash
kubectl get nodes -o wide
minikube status
```

### 8. Create Kubernetes registry authentication

```bash
kubectl create namespace container-platform
```

Create the image pull secret:

```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server="host.minikube.internal:80" \
  --docker-username="admin" \
  --docker-password="$HARBOR_PASSWORD" \
  --docker-email="admin@example.invalid" \
  -n container-platform
```

Verify:

```bash
kubectl get secret harbor-secret \
  -n container-platform
```

### 9. Deploy the application

```bash
kubectl apply \
  -f webapp-deployment.yaml
```

Wait for the rollout:

```bash
kubectl rollout status \
  deployment/webapp \
  -n container-platform \
  --timeout=300s
```

Verify all replicas:

```bash
kubectl get pods \
  -n container-platform \
  -o wide
```

### 10. Verify service connectivity

```bash
kubectl port-forward \
  service/webapp-service \
  8082:80 \
  -n container-platform
```

From another shell:

```bash
curl http://localhost:8082/
curl http://localhost:8082/health
```

### 11. Perform vulnerability scanning

Harbor with Trivy enabled scans stored image artifacts for known vulnerabilities.

Verify the scanner services:

```bash
cd ~/harbor
docker compose ps
```

Scan status and results can then be inspected through Harbor's artifact information and are retained in:

```text
evidence/vulnerability-scan-v1.0.json
```

### 12. Perform a controlled application update

The included update script:

- Builds a new image version
- Tags it for Harbor
- Pushes it to the private registry
- Updates the Kubernetes Deployment
- Waits for rollout completion

Run:

```bash
cd webapp
./update-app.sh v1.1
```

Verify the deployed image:

```bash
kubectl get deployment webapp \
  -n container-platform \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Inspect rollout history:

```bash
kubectl rollout history \
  deployment/webapp \
  -n container-platform
```

### 13. Enable Kubernetes resource metrics

```bash
minikube addons enable metrics-server
```

Wait for Metrics Server:

```bash
kubectl rollout status \
  deployment/metrics-server \
  -n kube-system \
  --timeout=300s
```

Inspect node usage:

```bash
kubectl top nodes
```

Inspect workload usage:

```bash
kubectl top pods \
  -n container-platform
```

### 14. Generate internal application traffic

```bash
kubectl run load-generator \
  --image=busybox:1.36 \
  --restart=Never \
  -n container-platform \
  -- \
  /bin/sh -c \
  'for i in $(seq 1 120); do wget -q -O- http://webapp-service/ >/dev/null; sleep 0.2; done'
```

Observe resource usage:

```bash
kubectl top pods \
  -n container-platform
```

Remove the temporary generator:

```bash
kubectl delete pod load-generator \
  -n container-platform
```

### 15. Enable Nginx Ingress

```bash
minikube addons enable ingress
```

Wait for the controller:

```bash
kubectl wait \
  --namespace ingress-nginx \
  --for=condition=Ready \
  pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s
```

Verify it:

```bash
kubectl get pods \
  -n ingress-nginx
```

### 16. Apply application routing

```bash
kubectl apply \
  -f webapp-ingress.yaml
```

Inspect routing:

```bash
kubectl get ingress \
  -n container-platform \
  -o wide
```

```bash
kubectl describe ingress \
  webapp-ingress \
  -n container-platform
```

### 17. Validate final workload state

```bash
kubectl get all \
  -n container-platform
```

```bash
kubectl get ingress \
  -n container-platform
```

```bash
kubectl top pods \
  -n container-platform
```

## Security Controls

The runtime and deployment implement several defensive controls:

- Application container runs as UID `1001`
- Root execution is disabled
- Privilege escalation is disabled
- Linux capabilities are dropped
- Build dependencies do not exist in the runtime image
- Health checks validate runtime availability
- Readiness probes prevent premature traffic delivery
- Liveness probes detect failed application instances
- CPU and memory boundaries are explicitly defined
- Private image pulls require Kubernetes registry credentials
- Registry artifacts are scanned with Trivy
- Versioned image tags support controlled updates

## Tools Used

- Docker Engine
- Docker Compose V2
- Docker multi-stage builds
- Nginx
- Node.js
- npm
- UglifyJS
- Harbor
- Trivy
- Kubernetes
- kubectl
- Minikube
- containerd
- Kubernetes Secrets
- Kubernetes Deployments
- Kubernetes Services
- Kubernetes Ingress
- Nginx Ingress Controller
- Metrics Server
- curl
- jq
- Bash

## Key Skills Demonstrated

- Designing multi-stage container build pipelines
- Separating build-time dependencies from runtime images
- Running containerized services as non-root identities
- Configuring Nginx for unprivileged execution
- Applying Linux capability restrictions
- Implementing application health checks
- Managing private container image storage
- Authenticating Kubernetes against private registries
- Deploying replicated Kubernetes workloads
- Defining CPU and memory requests and limits
- Implementing readiness and liveness probes
- Performing container vulnerability scanning
- Executing version-controlled rolling updates
- Monitoring Kubernetes resource consumption
- Generating internal application traffic
- Configuring service discovery
- Configuring and validating Ingress routing
- Troubleshooting admission webhooks
- Diagnosing container runtime permission failures
- Resolving host-to-cluster networking differences

## Real-World Use Case

This architecture fits organizations that require tighter control over software entering Kubernetes environments. Images can be built by CI systems, stored in a private Harbor registry, scanned for known vulnerabilities, and consumed only by workloads possessing the correct registry credentials. The same delivery pattern can support internal APIs, inference services, backend services, platform components, and other containerized workloads where repeatability, software supply-chain controls, runtime hardening, and operational visibility matter.

## Lessons Learned

- Multi-stage builds should be evaluated by runtime contents, not raw image size alone.
- A lightweight Nginx base can already be smaller than expected, so additional security tooling may slightly increase final image size.
- Moving to a non-root container requires attention to PID files, temporary directories, listener ports, filesystem ownership, and runtime permissions.
- `localhost` refers to different network namespaces depending on whether commands execute on the host, inside Minikube, or inside a workload.
- HTTP registries require explicit runtime configuration and should be replaced with trusted TLS endpoints in production.
- `kubectl top` depends on Metrics Server and should not be assumed to work automatically.
- An Ingress resource requires an active Ingress controller.
- Controller readiness does not necessarily mean its admission webhook is immediately accepting connections.
- Operational validation should test the actual service path instead of relying solely on successful resource creation.

## Troubleshooting Log

### Non-Root Nginx Startup Failure

The first hardened image successfully started as UID `1001`, but the container exited before accepting HTTP traffic.

The runtime attempted to use Nginx paths designed for privileged execution, including its default PID and temporary-file locations.

The configuration was corrected by:

- Moving the PID file to `/tmp/nginx.pid`
- Moving temporary Nginx paths under `/tmp`
- Listening on unprivileged port `8080`
- Assigning writable paths to UID `1001`
- Keeping privilege escalation disabled

The repaired container remained running and passed both HTTP and health checks.

### Multi-Stage Image Size Comparison

The hardened image was slightly larger than the basic Nginx image.

Observed comparison:

```text
webapp-basic:v1.0       93.6MB
webapp-optimized:v1.0   93.9MB
```

This was expected because the original runtime already used a minimal Alpine-based Nginx image while the hardened version added runtime health-check support.

The meaningful optimization was verified by confirming that Node.js and build dependencies were absent from the production runtime.

### Private Registry Network Address

Using an image reference based on host-side `localhost` does not work from inside a Minikube node because the node has its own network namespace.

Cluster-side image references therefore use:

```text
host.minikube.internal:80/platform-images/webapp:v1.0
```

This allows Minikube to reach Harbor running on the host.

### HTTP Registry Configuration

The isolated registry was operated over HTTP.

Docker and Minikube therefore required explicit insecure-registry configuration.

A production deployment should replace this with trusted TLS certificates and verified registry identities.

### Metrics API Availability

`kubectl top` initially cannot be assumed to work because the Kubernetes resource metrics API requires Metrics Server.

Metrics Server was enabled explicitly, allowed to become ready, and then verified before metrics were collected.

### Ingress Controller Dependency

An Ingress manifest alone does not create an HTTP routing implementation.

The Nginx Ingress Controller was enabled first, verified as Ready, and only then was application routing created.

### Admission Webhook Startup Race

The first Ingress creation attempt failed with an error similar to:

```text
failed calling webhook "validate.nginx.ingress.kubernetes.io":
connect: connection refused
```

The controller pod was already reported as Ready, but the admission webhook endpoint had not yet begun accepting connections.

The recovery process:

- Verified the admission service
- Verified endpoint registration
- Waited for controller stability
- Confirmed the validating webhook configuration
- Retried the Ingress creation
- Validated routing after the webhook became available

This demonstrated that Kubernetes component readiness and dependent webhook readiness can briefly diverge during startup.

## Validation Evidence

The `evidence/` directory contains runtime evidence captured from the final environment:

```text
deployment-final.yaml
service-final.yaml
ingress-final.yaml
pod-status.txt
pod-metrics.txt
vulnerability-scan-v1.0.json
```

These files capture the final Kubernetes workload configuration, service configuration, routing state, pod state, resource measurements, and registry vulnerability results.

## Production Improvements

For production deployment, the following improvements would be appropriate:

- Replace HTTP registry access with trusted TLS
- Use dedicated Harbor robot credentials instead of administrator credentials
- Integrate image scanning into CI before deployment
- Enforce vulnerability severity thresholds
- Sign images and verify signatures before admission
- Use immutable image digests rather than mutable tags
- Apply Kubernetes NetworkPolicies
- Add Pod Security Admission controls
- Use centralized metrics, logs, and alerting
- Store registry credentials in an external secrets system
- Add automated rollback conditions
- Run the registry and Kubernetes control plane on appropriately sized infrastructure
