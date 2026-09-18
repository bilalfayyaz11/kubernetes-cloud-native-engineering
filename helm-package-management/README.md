# Helm Package Management

## What This Does

This implementation demonstrates application lifecycle management on Kubernetes using Helm.

It covers:

- Helm repository management
- Chart discovery
- Apache deployment through a Helm chart
- Helm release inspection
- values-file customization
- replica scaling
- environment variable injection
- CPU and memory configuration
- command-line overrides
- revision history
- rollback
- template rendering
- dry-run debugging
- application validation
- release uninstall
- namespace cleanup

A compatibility issue caused by changes to the Bitnami public container catalog was also diagnosed and resolved during execution.

## Architecture

```text
                       +--------------------+
                       |       Helm         |
                       | release management |
                       +---------+----------+
                                 |
                                 v
                    +-------------------------+
                    | Bitnami Apache Chart    |
                    +------------+------------+
                                 |
                  values + overrides + upgrade
                                 |
                                 v
                    +-------------------------+
                    | Kubernetes Deployment   |
                    +------------+------------+
                                 |
                         +-------+-------+
                         |               |
                         v               v
                    +---------+     +---------+
                    | Apache  | ... | Apache  |
                    |  Pod    |     |  Pod    |
                    +----+----+     +----+----+
                         \               /
                          \             /
                           v           v
                         +---------------+
                         |   Service     |
                         |   ClusterIP   |
                         +-------+-------+
                                 |
                                 v
                         Port-forward / HTTP
```

## Repository Structure

```text
helm-package-management/
├── README.md
├── apache-chart-metadata.yaml
├── apache-default-values.yaml
├── apache-oci-chart-metadata.yaml
├── image-compatibility-values.yaml
├── custom-values.yaml
├── initial-release-values.yaml
├── initial-release-manifest.yaml
├── rendered-customized-release.yaml
├── revision-custom-values.yaml
├── final-release-values.yaml
├── final-release-manifest.yaml
└── evidence/
    ├── helm-history-before-rollback.txt
    ├── helm-history-after-rollback.txt
    ├── revision-1-values.yaml
    ├── current-values-before-rollback.yaml
    ├── current-manifest-before-rollback.yaml
    ├── rendered-template.yaml
    ├── helm-dry-run-debug.txt
    ├── live-resources.txt
    ├── service-endpointslice.yaml
    ├── events.txt
    ├── final-helm-status.txt
    └── final-release-values.yaml
```

## Prerequisites

- Ubuntu Linux
- Docker Engine
- kubectl
- Helm 4
- Minikube
- curl
- jq
- sudo access

## Kubernetes Environment

Start a local cluster:

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

## Helm Verification

Verify the installed Helm client:

```bash
helm version
```

The execution environment used:

```text
Helm v4.2.0
```

## Repository Configuration

Add Bitnami:

```bash
helm repo add bitnami \
  https://charts.bitnami.com/bitnami
```

Update repositories:

```bash
helm repo update
```

List repositories:

```bash
helm repo list
```

Search Apache charts:

```bash
helm search repo apache
```

Search Artifact Hub:

```bash
helm search hub apache
```

## Chart Inspection

View chart metadata:

```bash
helm show chart bitnami/apache
```

View chart defaults:

```bash
helm show values bitnami/apache
```

Save defaults:

```bash
helm show values bitnami/apache \
  > apache-default-values.yaml
```

## OCI Chart Discovery

OCI access can also be inspected with:

```bash
helm show chart \
  oci://registry-1.docker.io/bitnamicharts/apache
```

## Bitnami Image Compatibility Issue

The Apache chart referenced:

```text
docker.io/bitnami/apache:2.4.65-debian-12-r2
```

During deployment, Kubernetes returned:

```text
ErrImagePull
ImagePullBackOff
not found
```

The image had been moved as part of Bitnami's public catalog changes.

The corrected image repository used for compatibility was:

```text
docker.io/bitnamilegacy/apache:2.4.65-debian-12-r2
```

The compatibility values file:

```yaml
service:
  type: ClusterIP

image:
  registry: docker.io
  repository: bitnamilegacy/apache
  tag: 2.4.65-debian-12-r2

global:
  security:
    allowInsecureImages: true
```

## Install Apache

Create the namespace:

```bash
kubectl create namespace helm-management
```

Install:

```bash
helm install my-apache \
  bitnami/apache \
  --namespace helm-management \
  --values image-compatibility-values.yaml \
  --wait \
  --timeout 4m
```

## Verify Release

```bash
helm status my-apache \
  -n helm-management
```

```bash
helm list \
  -n helm-management
```

Verify resources:

```bash
kubectl get all \
  -n helm-management
```

## Verify Image

```bash
kubectl get pods \
  -n helm-management \
  -l app.kubernetes.io/instance=my-apache \
  -o jsonpath='{range .items[*]}{.metadata.name}{" -> "}{.spec.containers[0].image}{"\n"}{end}'
```

Expected repository:

```text
docker.io/bitnamilegacy/apache
```

## EndpointSlice Validation

```bash
kubectl get endpointslice \
  -n helm-management \
  -l kubernetes.io/service-name=my-apache \
  -o wide
```

This confirms that the Service has ready Kubernetes backends.

## HTTP Validation

```bash
kubectl port-forward \
  -n helm-management \
  svc/my-apache \
  8080:80
```

Then:

```bash
curl http://localhost:8080/
```

Expected result:

```text
HTTP 200
```

## Custom Values

Application customization:

```yaml
replicaCount: 3

service:
  type: ClusterIP

extraEnvVars:
  - name: APACHE_SERVER_NAME
    value: "my-custom-server"
  - name: ENVIRONMENT
    value: "development"

resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"
```

## Values Composition

The chart is upgraded using both the compatibility values and application values:

```bash
helm upgrade my-apache \
  bitnami/apache \
  --namespace helm-management \
  --values image-compatibility-values.yaml \
  --values custom-values.yaml \
  --wait \
  --timeout 5m
```

Using multiple values files keeps image compatibility separate from application configuration.

## Replica Scaling

Three replicas:

```yaml
replicaCount: 3
```

Verify:

```bash
kubectl get deployment \
  -n helm-management
```

CLI override to one replica:

```bash
helm upgrade my-apache \
  bitnami/apache \
  -n helm-management \
  -f image-compatibility-values.yaml \
  -f custom-values.yaml \
  --set replicaCount=1
```

Final override:

```bash
helm upgrade my-apache \
  bitnami/apache \
  -n helm-management \
  -f image-compatibility-values.yaml \
  -f custom-values.yaml \
  --set replicaCount=2 \
  --set service.type=ClusterIP \
  --set-json 'extraEnvVars=[{"name":"APP_ENV","value":"production"}]'
```

## Environment Variables

Verify variables in a running Pod:

```bash
kubectl exec \
  -n helm-management \
  deployment/my-apache \
  -- env
```

Expected examples:

```text
APACHE_SERVER_NAME=my-custom-server
ENVIRONMENT=development
```

Later CLI configuration:

```text
APP_ENV=production
```

## Resource Configuration

Requests:

```text
CPU:    50m
Memory: 64Mi
```

Limits:

```text
CPU:    100m
Memory: 128Mi
```

Inspect:

```bash
kubectl get deployment my-apache \
  -n helm-management \
  -o json \
  | jq '.spec.template.spec.containers[0].resources'
```

## Helm Revision History

```bash
helm history my-apache \
  -n helm-management
```

Each upgrade creates a new release revision.

## Revision Values

Inspect a historical revision:

```bash
helm get values my-apache \
  -n helm-management \
  --revision 1
```

## Helm Rollback

Rollback to an earlier revision:

```bash
helm rollback my-apache 1 \
  -n helm-management \
  --wait \
  --timeout 5m
```

Verify history:

```bash
helm history my-apache \
  -n helm-management
```

Rollback creates a new revision representing the restored configuration.

## Application Validation After Rollback

After rollback, application health was validated again through:

```bash
kubectl port-forward \
  -n helm-management \
  svc/my-apache \
  8080:80
```

and:

```bash
curl http://localhost:8080/
```

The application continued returning HTTP 200.

## Helm Template Rendering

Render resources without installing:

```bash
helm template my-apache \
  bitnami/apache \
  -n helm-management \
  -f image-compatibility-values.yaml \
  -f custom-values.yaml
```

This allows generated Kubernetes resources to be reviewed before applying them.

## Dry-Run Debugging

```bash
helm install my-apache-debug \
  bitnami/apache \
  -n helm-management \
  -f image-compatibility-values.yaml \
  -f custom-values.yaml \
  --dry-run \
  --debug
```

This provides:

- rendered manifests
- computed configuration
- template diagnostics
- release simulation without creating live resources

## Useful Helm Inspection Commands

Release status:

```bash
helm status my-apache \
  -n helm-management
```

Current values:

```bash
helm get values my-apache \
  -n helm-management \
  --all
```

Rendered manifest:

```bash
helm get manifest my-apache \
  -n helm-management
```

Release history:

```bash
helm history my-apache \
  -n helm-management
```

## Helm 4 Compatibility

Helm 4 differs from older Helm 3 examples in some command flags.

For example, old workflows may use:

```text
helm list --all
```

That option is not required in Helm 4.

The compatible release listing used here is:

```bash
helm list \
  -n helm-management
```

This distinction became important during troubleshooting because the unsupported flag caused an otherwise successful recovery workflow to terminate early under shell error handling.

## Troubleshooting Log

### Apache ImagePullBackOff

Observed:

```text
Failed to pull image
docker.io/bitnami/apache:2.4.65-debian-12-r2
not found
```

Resolution:

```text
docker.io/bitnamilegacy/apache:2.4.65-debian-12-r2
```

The image override was preserved during every subsequent Helm upgrade.

### Helm Wait Appeared to Hang

The initial install used:

```bash
helm install ... --wait --timeout 5m
```

Helm itself was not frozen.

It was waiting for Kubernetes resources to become Ready while the Apache Pod was stuck in:

```text
Init:ImagePullBackOff
```

Inspecting events exposed the actual image-pull failure.

### Helm 4 Unsupported Flag

A recovery step used:

```text
helm list --all
```

Helm 4 returned:

```text
unknown flag: --all
```

Because the shell was running with strict error handling, execution terminated immediately.

The command was replaced with:

```bash
helm list -n helm-management
```

### Image Override Preservation

Running a later upgrade without the compatibility values could cause the chart to render its original unavailable image again.

Every upgrade therefore explicitly included:

```text
image-compatibility-values.yaml
```

## Evidence Capture

The `evidence/` directory preserves:

- Helm history before rollback
- Helm history after rollback
- historical revision values
- current values
- rendered manifests
- dry-run debug output
- live Kubernetes resources
- EndpointSlice configuration
- Kubernetes events
- final Helm status

These artifacts provide evidence of the release lifecycle even after the live resources are removed.

## Cleanup

Uninstall release:

```bash
helm uninstall my-apache \
  -n helm-management
```

Verify:

```bash
helm list \
  -n helm-management
```

Delete namespace:

```bash
kubectl delete namespace helm-management
```

Local values, manifests, and evidence remain preserved.

## Key Skills Demonstrated

- Helm 4 package management
- Helm repository configuration
- Artifact Hub discovery
- OCI chart awareness
- chart metadata inspection
- default values inspection
- Helm release installation
- Kubernetes resource generation
- values-file composition
- environment-specific configuration
- replica management
- environment-variable injection
- resource requests and limits
- Helm CLI overrides
- release history inspection
- revision value inspection
- Helm rollback
- application health validation
- template rendering
- dry-run debugging
- EndpointSlice inspection
- image-pull troubleshooting
- container registry migration handling
- Helm major-version compatibility troubleshooting
- release uninstall
- Kubernetes namespace cleanup

## Real-World Use Case

Helm provides a repeatable application packaging and release-management layer above Kubernetes manifests.

This is particularly useful when deploying:

- API platforms
- databases
- observability stacks
- ingress controllers
- AI inference services
- internal developer platforms
- CI/CD components
- distributed applications with many configurable Kubernetes resources

Instead of maintaining separate hard-coded manifests for every environment, reusable charts can be combined with environment-specific values and release history.

## Lessons Learned

- Helm release success still depends on the health of underlying Kubernetes workloads.
- `--wait` can appear stuck when a Pod cannot become Ready; Kubernetes events should be inspected before assuming Helm itself has failed.
- Chart availability does not guarantee that every referenced container image is still available.
- Registry migrations can break otherwise valid historical charts.
- Compatibility values should be isolated so they remain explicit during upgrades.
- Helm upgrades create revision history that can be inspected and rolled back.
- Rollback should be followed by application-level health validation.
- `helm template` and `--dry-run --debug` are valuable before production changes.
- Major Helm versions can remove or change CLI options, so old operational scripts must be verified before reuse.
- Runtime evidence should be collected before uninstalling a release.
