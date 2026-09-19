# Kubernetes Multi-Environment Configuration with Kustomize

## Overview

This implementation demonstrates reusable Kubernetes configuration management with Kustomize using a shared application base and environment-specific staging and production overlays.

The configuration avoids duplicating complete Kubernetes manifests between environments. Common resources remain centralized, while overlays define only the differences required by each runtime environment.

The implementation covers:

- reusable Kustomize bases
- staging and production overlays
- namespace isolation
- environment-specific replica counts
- CPU and memory customization
- ConfigMap overrides
- container image transformation
- health probes
- rolling-update configuration
- generated ConfigMaps and Secrets
- modern unified patch syntax
- JSON6902-style transformations
- rendered-manifest validation
- live-state verification
- configuration inheritance
- troubleshooting and cleanup

## Architecture

    kubernetes-multi-environment-configuration/
    |
    +-- base/
    |   +-- deployment.yaml
    |   +-- service.yaml
    |   +-- configmap.yaml
    |   +-- kustomization.yaml
    |
    +-- overlays/
        |
        +-- staging/
        |   +-- namespace.yaml
        |   +-- deployment-patch.yaml
        |   +-- configmap-patch.yaml
        |   +-- kustomization.yaml
        |
        +-- production/
            +-- namespace.yaml
            +-- deployment-patch.yaml
            +-- configmap-patch.yaml
            +-- service-patch.yaml
            +-- cpu-limit-patch.json
            +-- kustomization.yaml

Configuration flow:

    Shared Base
        |
        +-----------------------+
        |                       |
        v                       v
     Staging                Production
        |                       |
        + 1 replica             + 3 replicas
        + debug config          + production config
        + lower resources       + higher resources
        + staging namespace     + health probes
                                + rolling updates
                                + targeted JSON patch

## Shared Base

The base contains resources common to both environments:

- Deployment
- Service
- ConfigMap
- Kustomization configuration

The application workload uses Nginx and exposes HTTP traffic through a ClusterIP Service.

The base provides a single source of truth for common Kubernetes configuration.

Render the base:

    kubectl kustomize base

## Staging Overlay

The staging overlay customizes the shared base for a lightweight non-production environment.

Key characteristics:

    Namespace: staging
    Replicas: 1
    Environment: staging
    Log level: debug

Resource profile:

    Requests:
      CPU: 50m
      Memory: 32Mi

    Limits:
      CPU: 150m
      Memory: 64Mi

Environment variable:

    ENVIRONMENT=staging

Staging configuration includes:

    environment=staging
    log_level=debug
    database_host=staging-db.internal
    debug_mode=true

Resource names use the staging prefix:

    staging-web-app
    staging-web-app-service
    staging-web-app-config

Render staging:

    kubectl kustomize overlays/staging

Deploy staging:

    kubectl apply -f overlays/staging/namespace.yaml
    kubectl apply -k overlays/staging

## Production Overlay

The production overlay applies stronger runtime configuration while still inheriting the same base.

Key characteristics:

    Namespace: production
    Replicas: 3
    Environment: production
    Log level: warn

Production includes:

- higher resource allocation
- rolling-update behavior
- startup probe
- readiness probe
- liveness probe
- production-specific configuration
- image transformation
- targeted CPU modification

Resource names use the production prefix:

    prod-web-app
    prod-web-app-service
    prod-web-app-config

Render production:

    kubectl kustomize overlays/production

Deploy production:

    kubectl apply -f overlays/production/namespace.yaml
    kubectl apply -k overlays/production

## Rolling Update Strategy

Production uses:

    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxSurge: 1
        maxUnavailable: 0

This allows Kubernetes to introduce replacement Pods without intentionally reducing the desired number of available replicas during the rollout.

## Health Probes

Production includes three health mechanisms.

### Startup Probe

Allows additional initialization time before other health checks control the container lifecycle.

### Readiness Probe

Determines whether the Pod should receive Service traffic.

### Liveness Probe

Detects an unhealthy running container and allows Kubernetes to restart it.

## Environment-Specific ConfigMaps

Both environments inherit the same base ConfigMap but override environment-specific values.

Staging:

    environment=staging
    log_level=debug
    database_host=staging-db.internal
    debug_mode=true

Production:

    environment=production
    log_level=warn
    database_host=prod-db.internal
    debug_mode=false
    cache_enabled=true
    max_connections=100

This demonstrates configuration reuse without maintaining independent copies of the entire resource.

## Image Management

The shared base defines the application image.

Kustomize can then transform the image through an overlay:

    images:
      - name: nginx
        newName: nginx
        newTag: 1.29.1-alpine

A shared image update was propagated through the configuration hierarchy and verified against the resulting live Deployments.

An important inheritance rule was also demonstrated:

    Base values propagate unless an overlay intentionally overrides the same field.

Reducing unnecessary overrides makes configuration ownership easier to understand.

## Modern Patch Configuration

Environment customization uses the unified Kustomize:

    patches:

interface.

Example:

    patches:
      - path: deployment-patch.yaml
      - path: configmap-patch.yaml

Production additionally targets a specific Deployment with a JSON patch.

## JSON Patch

Production applies a targeted operation to:

    /spec/template/spec/containers/0/resources/limits/cpu

The final production CPU limit becomes:

    750m

This demonstrates precise field-level transformation without duplicating a complete Deployment manifest.

## Generators

The base demonstrates both ConfigMap and Secret generators.

Generated configuration:

    runtime-settings-<hash>

Generated runtime metadata:

    runtime-credentials-<hash>

Kustomize automatically adds content-derived suffixes when generator hashing is enabled.

This makes configuration revisions visible through resource-name changes.

The committed configuration contains demonstration metadata only. Real credentials should be supplied at deployment time through an appropriate secret-management mechanism.

## Generated Resource Hashes

Generator output may resemble:

    runtime-settings-abc123
    runtime-credentials-def456

Changing generator input changes the generated resource name.

This behavior is useful for immutable-style configuration management and automated rollout workflows.

## Environment Isolation

Staging and production run in separate namespaces:

    staging
    production

Namespace objects are applied explicitly before their corresponding Kustomize overlays.

This avoids lifecycle ambiguity when validating or creating namespaced resources.

## Render Before Deployment

Configurations can be inspected before changing cluster state.

Base:

    kubectl kustomize base

Staging:

    kubectl kustomize overlays/staging

Production:

    kubectl kustomize overlays/production

This enables:

- manifest review
- CI validation
- policy evaluation
- configuration diffing
- troubleshooting
- GitOps reconciliation

## Replica Validation

Staging:

    kubectl get deployment \
      staging-web-app \
      -n staging \
      -o jsonpath='{.spec.replicas}'

Expected:

    1

Production:

    kubectl get deployment \
      prod-web-app \
      -n production \
      -o jsonpath='{.spec.replicas}'

Expected:

    3

## Resource Validation

Inspect staging resources:

    kubectl get deployment \
      staging-web-app \
      -n staging \
      -o jsonpath='{.spec.template.spec.containers[0].resources}'

Inspect production resources:

    kubectl get deployment \
      prod-web-app \
      -n production \
      -o jsonpath='{.spec.template.spec.containers[0].resources}'

This confirms that environment-specific transformations reached live cluster state.

## Runtime Configuration Validation

Staging:

    kubectl exec \
      -n staging \
      deployment/staging-web-app -- \
      env | grep ENVIRONMENT

Production:

    kubectl exec \
      -n production \
      deployment/prod-web-app -- \
      env | grep ENVIRONMENT

Expected values:

    ENVIRONMENT=staging

and:

    ENVIRONMENT=production

## Connectivity Validation

Application connectivity was validated from running Pods and through Kubernetes Service discovery.

Example Pod-local request:

    wget -qO- http://127.0.0.1/

Internal DNS names:

    staging-web-app-service.staging.svc.cluster.local

    prod-web-app-service.production.svc.cluster.local

This confirms that the generated Kubernetes resources were functional rather than only syntactically valid.

## Troubleshooting

### Overlay Does Not Render

Render the overlay directly:

    kubectl kustomize overlays/staging

or:

    kubectl kustomize overlays/production

Resolve rendering errors before deployment.

### Patch Does Not Apply

Check:

- resource kind
- resource name
- patch path
- field structure
- target selector

Then inspect the rendered output:

    kubectl kustomize overlays/production

### Namespace Not Found During Server Dry Run

A Namespace validated using server-side dry run is not persisted.

If later resources in the same dry-run stream target that Namespace, the API server may return:

    namespaces "<name>" not found

For reliable validation, create the Namespace first or validate the namespaced resources after the Namespace already exists.

### Base Change Does Not Propagate

An overlay may already own the same field through a patch or transformer.

Inspect:

    overlays/staging/kustomization.yaml

and:

    overlays/production/kustomization.yaml

Remove redundant overrides when the environment does not require different behavior.

## Validation Sequence

Recommended workflow:

    kubectl kustomize base

    kubectl kustomize overlays/staging

    kubectl kustomize overlays/production

Create namespaces:

    kubectl apply -f overlays/staging/namespace.yaml
    kubectl apply -f overlays/production/namespace.yaml

Deploy:

    kubectl apply -k overlays/staging
    kubectl apply -k overlays/production

Validate:

    kubectl rollout status \
      deployment/staging-web-app \
      -n staging

    kubectl rollout status \
      deployment/prod-web-app \
      -n production

## Evidence

The configuration was verified through:

- rendered base manifests
- rendered staging manifests
- rendered production manifests
- live replica comparison
- ConfigMap comparison
- resource request and limit validation
- health probe inspection
- rollout strategy inspection
- JSON patch verification
- generated resource verification
- workload connectivity testing
- cleanup verification

Supporting evidence files include:

    base-rendered-final.yaml
    staging-rendered-final.yaml
    production-rendered-final.yaml
    environment-comparison.txt
    kustomize-tree.txt

## Technologies

- Kubernetes
- K3s
- kubectl
- Kustomize
- YAML
- JSON Patch
- ConfigMaps
- generated resources
- Deployments
- Services
- Namespaces
- health probes
- rolling updates
- resource requests and limits
- Bash
- jq

## Engineering Skills Demonstrated

- Kubernetes configuration management
- reusable base architecture
- multi-environment overlay design
- configuration inheritance
- namespace isolation
- environment-specific configuration
- resource customization
- image transformation
- YAML patching
- JSON patching
- generated configuration
- health management
- rolling-update configuration
- render-first validation
- live-state verification
- Kubernetes troubleshooting
- DRY infrastructure configuration

## Operational Model

The same approach fits GitOps workflows where environment overlays are reconciled from version control.

A typical structure is:

    Shared Kubernetes Base
              |
        +-----+-----+
        |           |
        v           v
     Staging     Production
        |           |
        +-----+-----+
              |
              v
       GitOps Reconciliation

This keeps common application configuration centralized while preserving explicit environment-specific controls.

## Key Takeaways

- Keep shared Kubernetes configuration in one reusable base.
- Keep environment differences in overlays.
- Avoid complete manifest duplication.
- Render configuration before applying it.
- Validate both generated YAML and live Kubernetes resources.
- Keep namespace lifecycle explicit.
- Avoid redundant overrides that hide base changes.
- Prefer modern unified patch syntax.
- Use targeted JSON patches for precise changes.
- Keep real credentials outside version control.
- Use generated resource hashes to expose configuration revisions.
- Treat Kustomize as declarative configuration composition rather than a template engine.
