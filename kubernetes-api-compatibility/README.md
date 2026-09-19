# Kubernetes API Compatibility and Deprecation Management

## Overview

This implementation demonstrates a production-oriented workflow for identifying, migrating, validating, and monitoring Kubernetes API compatibility across cluster upgrades.

The workflow covers:

- discovery of deprecated and removed APIs
- validation of legacy manifests against a modern Kubernetes API server
- migration to supported stable API versions
- Deployment API modernization
- Ingress API modernization
- PodSecurityPolicy replacement
- Pod Security Admission enforcement
- client-side and server-side manifest validation
- workload functionality testing after migration
- API version inventory
- automated deprecation scanning
- CI-style compatibility enforcement
- operational troubleshooting
- upgrade-readiness documentation

The goal is to reduce upgrade risk by detecting incompatible Kubernetes resources before cluster version changes reach production.

## Compatibility Scenario

The compatibility workflow begins with deliberately outdated manifests containing API versions that are no longer served by modern Kubernetes.

Legacy examples include:

    extensions/v1beta1
    policy/v1beta1

The modern cluster is then used to demonstrate that removed APIs are rejected rather than merely generating warnings.

The resources are subsequently migrated to supported equivalents.

## Migration Architecture

    Legacy Manifests
          |
          v
    Static API Scan
          |
          v
    Modern Kubernetes API Server
          |
          +--> Removed API rejected
          |
          v
    Manifest Migration
          |
          +--> Deployment -> apps/v1
          |
          +--> Ingress -> networking.k8s.io/v1
          |
          +--> PodSecurityPolicy -> Pod Security Admission
          |
          v
    Client + Server Validation
          |
          v
    Functional Verification
          |
          v
    CI Compatibility Gate
          |
          v
    Continuous API Monitoring

## Legacy API Detection

The initial manifest set intentionally includes removed API references.

Examples:

    apiVersion: extensions/v1beta1

and:

    apiVersion: policy/v1beta1

These demonstrate the type of configuration that can block an application deployment after a Kubernetes control-plane upgrade.

The cluster API inventory is queried using:

    kubectl api-versions

and:

    kubectl api-resources

This establishes which API groups and versions are actually available on the running cluster.

## Modern API Server Validation

Legacy manifests are tested using both:

    kubectl apply --dry-run=client

and:

    kubectl apply --dry-run=server

Server-side validation is particularly important because it verifies compatibility against the actual Kubernetes API server.

Removed API versions are expected to fail.

This provides direct evidence that an application using those manifests would require migration before deployment to the current cluster.

## Deployment Migration

The legacy Deployment API:

    extensions/v1beta1

is migrated to:

    apps/v1

The current Deployment specification explicitly defines:

    spec.selector.matchLabels

and ensures that those selectors match the Pod template labels.

Example relationship:

    selector:
      app: nginx

    template:
      labels:
        app: nginx

This is required for a valid modern Deployment.

## Ingress Migration

The legacy Ingress API:

    extensions/v1beta1

is migrated to:

    networking.k8s.io/v1

Important structural changes include:

    serviceName
        ->
    backend.service.name

and:

    servicePort
        ->
    backend.service.port.number

Modern Ingress also requires a path type such as:

    pathType: Prefix

The resulting Ingress resource is validated against the running API server.

## Service Configuration

A ClusterIP Service provides a stable application endpoint:

    nginx-service

The Service selects:

    app: nginx

This allows application functionality to be tested independently from the API migration itself.

## Application Namespace

Migrated application resources run in:

    api-compatibility

This keeps compatibility testing isolated from unrelated cluster resources.

## PodSecurityPolicy Replacement

PodSecurityPolicy previously used:

    policy/v1beta1

The resource itself was removed from Kubernetes.

It is therefore not migrated to another PodSecurityPolicy API version.

Instead, the implementation uses Pod Security Admission with Pod Security Standards.

A dedicated namespace is configured with:

    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted

This applies the restricted Pod Security Standard at namespace level.

## Security Enforcement Validation

Two workloads are used to validate Pod Security Admission behavior.

### Privileged Workload

A Pod requesting:

    privileged: true

is submitted to the restricted namespace.

The API server rejects it.

This confirms that admission enforcement is active.

### Restricted-Compliant Workload

A compliant workload includes controls such as:

    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    seccompProfile:
      type: RuntimeDefault

The workload is admitted successfully.

This demonstrates migration from a removed security resource to the current admission model.

## Functional Validation

Migration success is not determined only by YAML syntax.

The implementation validates actual application behavior after migration.

Checks include:

- Deployment rollout completion
- expected ready replica count
- Pod state
- Service endpoint availability
- HTTP connectivity
- Ingress API structure
- admission-control behavior

Application connectivity is tested from inside the cluster.

Expected result:

    HTTP 200

This verifies that API modernization did not break application functionality.

## Client-Side Validation

Current manifests are checked using:

    kubectl apply --dry-run=client

This validates local manifest structure before resources are submitted.

## Server-Side Validation

The same resources are checked using:

    kubectl apply --dry-run=server

This verifies compatibility against the actual Kubernetes API server and its admission controls.

Server-side validation should be included in upgrade and release workflows whenever a target cluster is available.

## API Version Monitor

The script:

    monitor-api-versions.sh

collects operational compatibility information including:

- kubectl client version
- Kubernetes server version
- relevant served API versions
- removed API availability
- live Deployment APIs
- live Ingress APIs
- Pod Security namespace configuration

This provides a repeatable compatibility snapshot for cluster operators.

## Static Deprecation Scanner

The script:

    check-deprecations.sh

scans YAML manifests for known removed APIs.

Examples detected include:

    extensions/v1beta1
    policy/v1beta1

This provides a lightweight local inspection mechanism.

## CI Compatibility Gate

The script:

    ci-api-compatibility-check.sh

implements an automated compatibility gate suitable for CI pipelines.

It checks manifest files for API versions including:

    extensions/v1beta1
    policy/v1beta1
    apps/v1beta1
    apps/v1beta2
    networking.k8s.io/v1beta1

If a configured removed API is found, the script exits with a failure code.

This allows incompatible manifests to be blocked before deployment.

## Negative and Positive CI Tests

The compatibility gate is tested against two manifest sets.

### Legacy Set

The intentionally outdated manifests contain removed APIs.

Expected result:

    FAILED

### Migrated Set

The modern manifests contain supported API versions.

Expected result:

    PASSED

This proves that the gate can distinguish known incompatible configurations from migrated resources.

## Deprecation Alerting

The script:

    deprecation-alert.sh

performs recurring checks against both:

- API versions served by the cluster
- migrated manifest content

It generates:

    deprecation-alert-report.txt

This pattern can be integrated into scheduled operational checks or CI/CD systems.

## Migration Checklist

The file:

    api-migration-checklist.md

documents a reusable migration process covering:

### Pre-Migration

- manifest inventory
- Kubernetes version identification
- removed API identification
- breaking-change review
- rollback planning

### Migration

- API version replacement
- structural field changes
- security-model replacement
- client validation
- server validation

### Verification

- workload rollout
- Service connectivity
- admission controls
- events
- compatibility scanning

### Post-Migration

- remove remaining legacy references
- update documentation
- monitor cluster APIs
- schedule recurring compatibility checks

## Troubleshooting API Compatibility

Useful commands include:

    kubectl api-versions

    kubectl api-resources

    kubectl explain ingress.spec.rules.http.paths.backend

    kubectl apply --dry-run=server -f <manifest>

    kubectl get events --sort-by=.metadata.creationTimestamp

These commands help distinguish:

- unsupported API versions
- invalid manifest structure
- admission-policy violations
- missing controllers
- runtime workload problems

## Ingress Troubleshooting

An API-valid Ingress does not guarantee external routing.

The environment is checked for:

    kubectl get ingressclass

If no Ingress controller is installed, the resource can still be valid and stored successfully, but external routing is not expected.

This separates API compatibility from controller availability.

## Pod Security Troubleshooting

Pod Security Admission failures can be investigated using:

    kubectl get namespace <namespace> --show-labels

and:

    kubectl get events -n <namespace>

Workload security contexts should then be reviewed against the namespace's configured Pod Security level.

## API Compatibility Inventory

The workflow produces a final compatibility report containing:

- client version
- server version
- relevant served APIs
- removed API availability
- live Deployment API version
- live Ingress API version
- Pod Security enforcement labels

This provides upgrade-readiness evidence rather than relying on assumptions about cluster compatibility.

## Automation Artifacts

Operational scripts include:

    check-deprecations.sh
    monitor-api-versions.sh
    ci-api-compatibility-check.sh
    deprecation-alert.sh

Documentation includes:

    api-changes-summary.md
    api-migration-checklist.md

## Evidence

Representative evidence generated during validation includes:

    deprecated-deployment-client.txt
    deprecated-deployment-server.txt
    deprecated-psp-client.txt
    deprecated-psp-server.txt
    initial-deprecation-scan.txt
    post-migration-deprecation-scan.txt
    migration-functional-validation.txt
    privileged-pod-result.txt
    pod-security-events.txt
    api-version-monitor-report.txt
    ci-legacy-scan.txt
    ci-current-scan.txt
    deprecation-alert-report.txt
    api-compatibility-inventory.txt
    final-ingress-description.txt
    final-privileged-denial.txt
    final-pod-security-events.txt
    final-static-deprecation-scan.txt
    final-api-version-monitor.txt
    final-ci-compatibility-check.txt
    final-deprecation-alert-report.txt
    final-api-compatibility-report.txt

## Technologies

- Kubernetes
- K3s
- kubectl
- Bash
- jq
- YAML
- Deployments
- Services
- Ingress
- Pod Security Admission
- Pod Security Standards
- Kubernetes API discovery
- client-side dry-run
- server-side dry-run
- CI compatibility checks

## Engineering Skills Demonstrated

- Kubernetes API lifecycle management
- cluster upgrade compatibility analysis
- deprecated API detection
- removed API identification
- manifest migration
- Deployment API modernization
- Ingress migration
- Pod Security Admission
- security-context validation
- client/server dry-run validation
- CI policy enforcement
- Bash automation
- API inventory generation
- operational troubleshooting
- upgrade-risk reduction

## Upgrade Safety Model

A safe Kubernetes upgrade workflow can be represented as:

    Current Cluster
         |
         v
    Inventory APIs
         |
         v
    Scan Manifests
         |
         +--> Removed API found
         |        |
         |        v
         |     Migrate
         |
         v
    Validate Against Target API Server
         |
         v
    Functional Verification
         |
         v
    CI Compatibility Gate
         |
         v
    Cluster Upgrade

This shifts compatibility failures left, before they become production outages.

## Key Takeaways

- Kubernetes API deprecation must be managed before version upgrades.
- Deprecated and removed APIs are different operational states.
- Removed APIs can prevent manifests from being accepted entirely.
- `apps/v1` is the supported Deployment API.
- `networking.k8s.io/v1` requires structural Ingress changes.
- PodSecurityPolicy was removed rather than replaced with a newer PSP version.
- Pod Security Admission provides the modern built-in enforcement model.
- Client-side validation alone is not sufficient for upgrade readiness.
- Server-side dry-run verifies compatibility against the actual API server.
- Application functionality must be tested after manifest migration.
- Negative security tests provide evidence that admission controls are active.
- Static scanning can detect many compatibility issues before deployment.
- CI gates can prevent removed APIs from entering deployment pipelines.
- API inventories and migration checklists improve upgrade planning.
- Recurring compatibility monitoring reduces future cluster upgrade risk.
