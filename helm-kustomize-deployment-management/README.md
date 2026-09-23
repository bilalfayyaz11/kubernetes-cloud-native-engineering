# Helm and Kustomize Deployment Management

## What This Does

This implementation builds and validates two complementary Kubernetes application-delivery workflows.

Helm is used for package-driven deployment and release lifecycle management, including installation, configuration through values, upgrades, revision history, rollback, and custom chart authoring.

Kustomize is used for native Kubernetes configuration management with a reusable base and environment-specific overlays for development, staging, and production.

Both approaches are rendered, deployed, validated against a live Kubernetes cluster, compared operationally, updated, troubleshot, and cleaned up.

## Architecture

```text
                         Kubernetes Cluster
                                 |
              +------------------+------------------+
              |                                     |
              v                                     v
       Helm Workflow                         Kustomize Workflow
              |                                     |
      +-------+-------+                         Shared Base
      |               |                              |
      v               v                  +-----------+-----------+
Third-Party       Custom Helm            |           |           |
NGINX Chart          Chart               v           v           v
      |               |            Development   Staging    Production
      |               |              Overlay      Overlay      Overlay
      +-------+-------+                  |           |           |
              |                          +-----------+-----------+
              v                                      |
    Install / Upgrade /                              v
          Rollback                            kubectl apply -k
              |                                      |
              +------------------+-------------------+
                                 |
                                 v
                      Kubernetes Deployments
```

## Prerequisites

- Ubuntu or compatible Linux environment
- Docker-compatible container runtime
- Kubernetes cluster
- kubectl
- Helm
- Kustomize
- Git
- curl
- tree

Validated environment:

- Ubuntu 24.04 LTS
- Kubernetes through kind
- kubectl 1.36.x
- Helm 4.x
- Kustomize 5.x
- Docker

## Setup & Installation

### Kubernetes Cluster

A dedicated kind cluster was used as the Kubernetes runtime.

```bash
kind create cluster \
  --name helm-kustomize \
  --config kind-config.yaml
```

Verify cluster health:

```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -n kube-system
```

### Helm Repository

Configure the Bitnami chart repository:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm repo list
```

The historical Helm stable repository is intentionally excluded.

### Kustomize

Verify both supported renderers:

```bash
kustomize version
kubectl kustomize --help
```

## How to Reproduce

### 1. Inspect a Third-Party Helm Chart

Search available charts:

```bash
helm search repo nginx
helm search repo mysql
```

Inspect nginx metadata and defaults:

```bash
helm show chart bitnami/nginx
helm show values bitnami/nginx
```

Download the chart for structural inspection:

```bash
helm pull bitnami/nginx \
  --untar \
  --untardir chart-inspection
```

Inspect the chart:

```bash
tree -L 2 chart-inspection/nginx
helm lint chart-inspection/nginx
```

### 2. Deploy NGINX with Helm

Create the namespace:

```bash
kubectl create namespace helm-demo
```

Deploy a standard nginx release:

```bash
helm install my-nginx \
  bitnami/nginx \
  --namespace helm-demo
```

Deploy a second release with custom values:

```bash
helm install custom-nginx \
  bitnami/nginx \
  --namespace helm-demo \
  --values custom-nginx-values.yaml
```

The custom configuration starts with:

- 3 replicas
- NodePort exposure
- explicit CPU requests and limits
- explicit memory requests and limits
- disabled ingress

Verify:

```bash
helm status custom-nginx -n helm-demo
helm list -n helm-demo
kubectl get all -n helm-demo
```

### 3. Exercise the Helm Release Lifecycle

Scale the release to five replicas:

```bash
helm upgrade custom-nginx \
  bitnami/nginx \
  --namespace helm-demo \
  --reuse-values \
  --set replicaCount=5
```

Inspect revision history:

```bash
helm history custom-nginx \
  --namespace helm-demo
```

Rollback:

```bash
helm rollback custom-nginx 1 \
  --namespace helm-demo
```

The verified lifecycle was:

```text
Revision 1
3 replicas
    |
    v
Revision 2
5 replicas
    |
    v
Revision 3
Rollback to revision 1
    |
    v
3 replicas
```

### 4. Create a Custom Helm Chart

Generate a chart:

```bash
helm create my-webapp
```

The chart was configured with:

- nginx:1.28-alpine
- 2 replicas
- ClusterIP service
- CPU and memory requests
- CPU and memory limits
- readiness probe
- liveness probe
- configurable autoscaling values

Lint the chart:

```bash
helm lint my-webapp
```

Render it:

```bash
helm template my-custom-app \
  ./my-webapp \
  --namespace helm-demo \
  > my-webapp-rendered.yaml
```

Validate against Kubernetes:

```bash
kubectl apply \
  --dry-run=server \
  -f my-webapp-rendered.yaml
```

Deploy:

```bash
helm install my-custom-app \
  ./my-webapp \
  --namespace helm-demo
```

Verify:

```bash
helm status my-custom-app -n helm-demo
kubectl get all \
  -n helm-demo \
  -l app.kubernetes.io/instance=my-custom-app
```

### 5. Build a Reusable Kustomize Base

Directory structure:

```text
kustomize/
└── base/
    ├── deployment.yaml
    ├── service.yaml
    └── kustomization.yaml
```

The base defines:

- nginx workload
- ClusterIP service
- resource requests and limits
- readiness probe
- liveness probe
- common management labels

Render the base:

```bash
kubectl kustomize kustomize/base
```

The standalone renderer can also be used:

```bash
kustomize build kustomize/base
```

### 6. Build Environment-Specific Overlays

The overlay structure is:

```text
kustomize/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── development/
    │   ├── deployment-patch.yaml
    │   └── kustomization.yaml
    ├── staging/
    │   ├── deployment-patch.yaml
    │   ├── service-patch.yaml
    │   └── kustomization.yaml
    └── production/
        ├── deployment-patch.yaml
        └── kustomization.yaml
```

Environment characteristics:

| Environment | Replicas | Service Type | CPU Request | Memory Request |
|---|---:|---|---|---|
| Development | 1 | ClusterIP | 25m | 32Mi |
| Staging | 2 | NodePort | 50m | 64Mi |
| Production | 5 | ClusterIP | 100m | 128Mi |

Each environment also receives its own `ENVIRONMENT` variable.

Development:

```text
ENVIRONMENT=development
```

Staging:

```text
ENVIRONMENT=staging
```

Production:

```text
ENVIRONMENT=production
```

### 7. Deploy the Kustomize Environments

Create namespaces:

```bash
kubectl create namespace development
kubectl create namespace staging
kubectl create namespace production
```

Deploy:

```bash
kubectl apply -k kustomize/overlays/development
kubectl apply -k kustomize/overlays/staging
kubectl apply -k kustomize/overlays/production
```

Verify rollouts:

```bash
kubectl rollout status deployment/webapp -n development
kubectl rollout status deployment/webapp -n staging
kubectl rollout status deployment/webapp -n production
```

Verify resources:

```bash
kubectl get all -n development
kubectl get all -n staging
kubectl get all -n production
```

The staging configuration additionally exposes the application through:

```text
NodePort 30081
```

### 8. Compare Helm and Kustomize

Helm configurations were rendered with environment-specific values.

Example:

```bash
helm template my-webapp \
  ./my-webapp \
  --namespace production \
  --set replicaCount=5 \
  --set image.tag=1.28-alpine
```

Kustomize configurations were rendered through overlays:

```bash
kubectl kustomize kustomize/overlays/development
kubectl kustomize kustomize/overlays/staging
kubectl kustomize kustomize/overlays/production
```

Generated comparison artifacts include:

```text
comparison-helm-development.yaml
comparison-helm-production.yaml
comparison-kustomize-development.yaml
comparison-kustomize-staging.yaml
comparison-kustomize-production.yaml
deployment-comparison.md
```

## Helm vs Kustomize

| Capability | Helm | Kustomize |
|---|---|---|
| Package management | Yes | No |
| Release history | Yes | No |
| Built-in rollback | Yes | No |
| Configuration model | Templates and values | Bases and patches |
| Dependency management | Yes | No |
| Native Kubernetes YAML | Partial | Yes |
| Environment customization | Values | Overlays |
| Built into kubectl | No | Yes |
| GitOps compatibility | Strong | Strong |
| Third-party software deployment | Strong | Limited |
| Environment-specific configuration | Strong | Strong |

Helm is primarily focused on reusable application packaging and release lifecycle management.

Kustomize is primarily focused on declarative customization of native Kubernetes resources.

They can also complement one another in larger platform and GitOps workflows.

## Tools Used

- Kubernetes
- kind
- kubectl
- Helm
- Kustomize
- Docker
- NGINX
- Bash
- Git

## Key Skills Demonstrated

- Kubernetes application packaging
- Helm chart consumption
- Helm chart authoring
- Helm values management
- Helm release upgrades
- Helm rollback operations
- Release revision analysis
- Kubernetes manifest rendering
- Kubernetes API validation
- Kustomize base design
- Kustomize overlays
- Environment-specific configuration
- Patch-based resource customization
- Resource requests and limits
- Service exposure
- Deployment rollout verification
- Runtime troubleshooting
- Declarative infrastructure management
- Lifecycle cleanup

## Real-World Use Case

Platform engineering teams frequently need both reusable software packaging and environment-specific Kubernetes configuration.

Helm provides packaging, parameterization, dependency support, revision tracking, upgrades, and rollback.

Kustomize provides a Kubernetes-native approach for maintaining shared manifests while expressing controlled differences between development, staging, and production.

A practical platform workflow can therefore use Helm for reusable application packages and release lifecycle management while using Kustomize for GitOps-oriented environment configuration.

## Lessons Learned

- Helm and Kustomize solve related but different Kubernetes configuration problems.
- Helm revision history provides operational lifecycle capabilities beyond plain manifest customization.
- Kustomize overlays make environment differences explicit and reviewable.
- Rendered Kubernetes manifests should be validated before deployment.
- Namespace existence affects server-side validation of namespaced objects.
- Third-party Helm charts should not be assumed compatible with arbitrary replacement container images.
- Container images and chart runtime assumptions must be evaluated together.
- Explicit resource requests and limits are preferable to relying on generic presets.
- Rollbacks should be verified against actual live Kubernetes state.
- Cleanup verification is part of a reliable deployment lifecycle.
- Configuration source should remain preserved after runtime resources are removed.

## Troubleshooting Log

### Missing Kubernetes Cluster

The environment contained kubectl and Helm but had no Kubernetes context or running cluster.

A dedicated kind cluster was created before deployment operations began.

### Deprecated Helm Repository

Older procedures referenced the historical Helm stable repository.

That repository was intentionally excluded and actively maintained repositories were used instead.

### Bitnami Image Compatibility

An initial configuration replaced the image expected by the Bitnami nginx chart with the upstream nginx image.

The resulting pods entered:

```text
Init:CrashLoopBackOff
Init:RunContainerError
```

The chart contained initialization, filesystem, and security assumptions associated with its own image.

The incompatible override was removed.

The deployment then reached:

```text
3/3 Ready
```

### Helm Upgrade and Rollback

The custom nginx release was upgraded from three replicas to five replicas.

Release history confirmed separate installation and upgrade revisions.

Rollback to revision 1 successfully restored:

```text
Configured replicas: 3
Ready replicas: 3
```

### Server-Side Kustomize Validation

Initial server-side validation returned:

```text
namespaces "development" not found
namespaces "staging" not found
namespaces "production" not found
```

The rendered resources were valid.

The target namespaces intentionally did not exist yet because deployment had not begun.

Client-side validation was used before deployment, followed by server-side validation after namespace creation.

### Kustomize Patch Modernization

Older configuration patterns used `patchesStrategicMerge`.

The overlay definitions were implemented with the current generic `patches` structure.

### Unsafe YAML Append

Appending a new environment variable directly to an existing YAML patch could place the new list item under an incorrect YAML node.

The development deployment patch was regenerated deterministically with:

```text
ENVIRONMENT=development
DEBUG=true
```

The updated deployment rolled out successfully.

### Runtime Cleanup

After verification, the following were removed from the cluster:

- Helm releases
- development workloads
- staging workloads
- production workloads
- helm-demo namespace
- development namespace
- staging namespace
- production namespace

Source configuration, rendered manifests, comparison documents, and verification evidence were preserved for reproducibility.
