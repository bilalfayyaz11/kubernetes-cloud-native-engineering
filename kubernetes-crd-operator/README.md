# Kubernetes Custom Resources and Controller Engineering

## Overview

This implementation extends Kubernetes with a namespaced custom API and a dedicated controller that manages application resources declaratively.

The custom resource is:

    apiVersion: platform.example/v1
    kind: WebApp

A WebApp defines:

    replicas
    container image
    application port
    environment variables

The controller continuously reconciles that desired state into Kubernetes Deployments and Services, updates custom-resource status, repairs configuration drift, and establishes owner references so managed resources are removed automatically when their parent custom resource is deleted.

## Architecture

    +--------------------------------------------------+
    |              Kubernetes API Server               |
    +-------------------------+------------------------+
                              |
                              v
                   platform.example/v1
                              |
                              v
                         +---------+
                         | WebApp  |
                         +---------+
                              |
                      desired state
                              |
                              v
               +---------------------------+
               | WebApp Controller         |
               | namespace-scoped RBAC     |
               +---------------------------+
                    |                 |
                    v                 v
             +-------------+    +-------------+
             | Deployment  |    | Service     |
             +-------------+    +-------------+
                    |
                    v
                  Pods

The custom resource is the source of truth for the managed workload.

## Environment

The implementation runs on:

    Ubuntu 24.04 LTS
    Docker Engine
    kubectl
    kind

Kubernetes cluster:

    kind
    Kubernetes v1.36.1

Topology:

    1 control-plane node

A single-node cluster is sufficient for validating Kubernetes API extension, reconciliation, RBAC, status subresources, owner references, validation schema behavior, and garbage collection.

## Custom Resource Definition

The API extension registers:

    Group:
    platform.example

    Version:
    v1

    Resource:
    webapps

    Kind:
    WebApp

    Short name:
    wa

    Scope:
    Namespaced

The CRD uses:

    apiextensions.k8s.io/v1

## OpenAPI Schema Validation

The WebApp schema validates application configuration before the custom resource is accepted by the Kubernetes API server.

Required fields:

    replicas
    image
    port

Replica constraints:

    minimum: 1
    maximum: 10

Port constraints:

    minimum: 1
    maximum: 65535

Environment variables are represented as structured name/value entries.

Invalid resources are rejected before reaching the controller.

Examples tested include:

    replicas: 11

and resources missing:

    image
    port

Both were rejected by the API server through CRD schema validation.

## Status Subresource

The CRD enables:

    status: {}

as a dedicated status subresource.

The controller records observed state separately from desired state.

Status fields include:

    observedGeneration
    availableReplicas
    conditions

The Ready condition reports:

    type
    status
    observedGeneration
    lastTransitionTime
    reason
    message

Example interpretation:

    spec.replicas
        desired replica count

    status.availableReplicas
        replicas currently available

    status.observedGeneration
        custom-resource generation processed by the controller

This allows consumers to distinguish requested configuration from observed runtime state.

## Additional Printer Columns

The custom resource exposes operational fields through standard kubectl output.

Examples include:

    Replicas
    Available
    Image
    Ready

This makes:

    kubectl get webapps

useful as an operational status view rather than only an object listing.

## Controller Design

The controller is implemented in Python using the Kubernetes Python client.

It runs inside the cluster as a Deployment and uses in-cluster authentication.

The main reconciliation loop:

    discovers WebApp resources
    reconciles Deployment state
    reconciles Service state
    refreshes WebApp status
    repeats at a controlled interval

The controller does not rely on shelling out to kubectl from inside the container.

## Namespace-Scoped Discovery

The controller intentionally watches WebApp resources in a configured namespace.

It uses:

    list_namespaced_custom_object

rather than cluster-wide custom-resource discovery.

This aligns runtime behavior with namespace-scoped RBAC.

The controller therefore has:

    namespaced WebApp list access: allowed

while:

    cluster-wide WebApp list access: denied

This preserves least-privilege behavior.

## RBAC

The controller runs under a dedicated ServiceAccount:

    webapp-controller

Its Role grants only the capabilities required for reconciliation.

The controller can:

    get WebApp resources
    list WebApp resources
    watch WebApp resources
    patch WebApp status
    update WebApp status
    create Deployments
    read Deployments
    patch Deployments
    update Deployments
    create Services
    read Services
    update Services
    patch Services
    inspect Pods

The design deliberately avoids unnecessary cluster-wide permissions.

## Deployment Reconciliation

Each WebApp produces a managed Deployment.

The controller reconciles:

    replicas
    image
    container port
    environment variables
    labels
    resource requests
    resource limits
    owner references

The Deployment includes labels linking it back to the WebApp.

Example ownership label:

    platform.example/webapp=<name>

## Service Reconciliation

Each WebApp produces a ClusterIP Service.

The Service reconciles:

    selector
    port
    targetPort
    labels
    owner references

Service reconciliation required extra care because Service networking fields are partly assigned by the Kubernetes API server.

The final implementation serializes the live Service through the Kubernetes client, preserves API-assigned networking values, then replaces the Service using the complete desired port list.

Preserved fields include:

    clusterIP
    clusterIPs
    ipFamilies
    ipFamilyPolicy
    sessionAffinity
    internalTrafficPolicy when present

This avoids stale or duplicate Service-port entries while retaining the allocated ClusterIP.

## Continuous Reconciliation

The controller was validated as a continuous reconciler rather than a one-time resource generator.

The WebApp was changed from its initial configuration to:

    replicas: 5
    image: nginx:1.28-alpine
    port: 8080

Environment configuration was updated to:

    ENV_TYPE=staging
    LOG_LEVEL=debug
    FEATURE_FLAG=enabled

The controller propagated those changes automatically to the Deployment and Service.

The WebApp status subsequently converged to the new generation.

## Drift Correction

Several forms of direct child-resource drift were deliberately introduced.

### Replica Drift

The managed Deployment was manually scaled away from the WebApp specification.

The controller restored:

    replicas: 5

without changing the parent WebApp.

### Image Drift

The Deployment image was manually changed.

The controller restored:

    nginx:1.28-alpine

### Environment Drift

Managed environment variables were manually changed.

The controller restored the values declared in:

    WebApp.spec.env

### Service Port Drift

The managed Service port was deliberately changed away from the desired value.

The controller restored:

    port: 8080
    targetPort: 8080

These scenarios demonstrate that the custom resource remains the authoritative desired state.

## Owner References

Managed Deployments and Services contain controller owner references to their parent WebApp.

The owner reference includes:

    apiVersion
    kind
    name
    uid
    controller
    blockOwnerDeletion

This establishes a Kubernetes-native resource hierarchy.

The controller does not need to manually delete every child resource when a parent is removed.

## Multi-Resource Reconciliation

The controller was tested with more than one WebApp at the same time.

A second WebApp requested:

    replicas: 2
    image: httpd:2.4-alpine
    port: 80

The controller independently created and reconciled:

    secondary-webapp-deployment
    secondary-webapp-service

while continuing to manage the original WebApp.

This validated that reconciliation is resource-driven rather than hardcoded to one application.

## Kubernetes Garbage Collection

The secondary WebApp was deleted after its child resources had valid owner references.

Observed result:

    WebApp removed
    Deployment removed
    Service removed

No manual child-resource deletion was required.

The primary WebApp and its managed workload remained unaffected.

This demonstrates native Kubernetes garbage collection through owner references.

## Troubleshooting and Recovery

Several controller defects were intentionally preserved as troubleshooting evidence during implementation and then corrected.

### RBAC Scope Mismatch

Initial behavior used cluster-scoped custom-resource listing while the controller had namespace-scoped Role permissions.

Observed result:

    HTTP 403 Forbidden

Correction:

    list_cluster_custom_object
        replaced with
    list_namespaced_custom_object

The controller retained the tighter namespace-scoped RBAC model.

### Owner Reference Serialization

An earlier implementation converted typed owner-reference objects using Python field names.

That generated fields such as:

    api_version
    block_owner_deletion

Kubernetes expects:

    apiVersion
    blockOwnerDeletion

The reconciliation path was corrected to construct Kubernetes API dictionaries using canonical field names.

### Service Strategic Merge Behavior

Strategic patching of Service ports can treat the port value as a merge key.

Changing a port could therefore leave conflicting entries rather than representing a complete desired list.

The final implementation uses full Service replacement while preserving API-managed networking data.

### Kubernetes Client Attribute Compatibility

The generated Python Service model exposed implementation-specific attribute naming for fields such as clusterIPs.

Instead of depending on internal model attribute names, the final implementation uses:

    client.ApiClient().sanitize_for_serialization()

This yields canonical Kubernetes API field names and reduces generated-client coupling.

### Status Synchronization

The Deployment reached:

    5/5 Ready

while the WebApp status temporarily remained:

    4/5
    Ready=False

The root cause was not status calculation itself. Service reconciliation failed before execution reached the status update.

Once Service reconciliation was corrected, the complete reconcile cycle reached:

    update_status(webapp)

and the custom resource converged to:

    availableReplicas: 5
    Ready: True
    observedGeneration: current generation

## Final State

The final managed custom resource is:

    my-web-application

Desired replicas:

    5

Available replicas:

    5

Image:

    nginx:1.28-alpine

Port:

    8080

Ready condition:

    True

Final WebApp resource count:

    1

Controller state:

    Ready

Controller logs:

    clean

## Validation Matrix

    Kubernetes cluster
    PASS

    CRD established
    PASS

    Custom API registration
    PASS

    OpenAPI schema
    PASS

    Invalid replica rejection
    PASS

    Required field enforcement
    PASS

    Status subresource
    PASS

    Additional printer columns
    PASS

    Namespace-scoped RBAC
    PASS

    Cluster-wide custom-resource listing denied
    PASS

    Controller Deployment
    PASS

    Deployment reconciliation
    PASS

    Service reconciliation
    PASS

    Replica drift correction
    PASS

    Image drift correction
    PASS

    Environment drift correction
    PASS

    Service drift correction
    PASS

    Status synchronization
    PASS

    Owner references
    PASS

    Multi-resource reconciliation
    PASS

    Automatic Deployment garbage collection
    PASS

    Automatic Service garbage collection
    PASS

    Primary workload retained after secondary deletion
    PASS

    Controller log health
    PASS

## Repository Structure

    kubernetes-crd-operator/
    |
    +-- README.md
    |
    +-- manifests/
    |   +-- kind-cluster.yaml
    |   +-- webapp-crd.yaml
    |   +-- sample-webapp.yaml
    |   +-- controller-rbac.yaml
    |   +-- controller-deployment.yaml
    |   +-- secondary-webapp.yaml
    |
    +-- controller/
    |   +-- Dockerfile
    |   +-- requirements.txt
    |   +-- webapp-controller.py
    |
    +-- scripts/
    |   +-- monitor-webapp-controller.sh
    |
    +-- evidence/
        +-- final-validation.txt
        +-- final-architecture.txt
        +-- final-webapp.yaml
        +-- final-managed-deployment.yaml
        +-- final-managed-service.yaml
        +-- final-managed-pods.txt
        +-- final-controller.log
        +-- final-events.txt
        +-- final-invalid-resource-rejection.txt
        +-- multi-resource-garbage-collection.txt
        +-- final-garbage-collection-recovery.txt
        +-- drift-correction-validation.txt
        +-- service-reconciliation-recovery.txt
        +-- controller-v106-recovery.txt

## Skills Demonstrated

This implementation demonstrates practical experience with:

- Kubernetes API extension
- CustomResourceDefinition
- custom resources
- OpenAPI v3 schema validation
- status subresources
- additional printer columns
- Python Kubernetes client
- reconciliation loops
- declarative desired state
- Deployment management
- Service management
- owner references
- Kubernetes garbage collection
- ServiceAccount
- Role
- RoleBinding
- least-privilege RBAC
- namespace-scoped controllers
- controller status management
- drift detection
- drift correction
- controller containerization
- kind
- kubectl
- Kubernetes troubleshooting
- API error diagnosis
- custom-controller operational monitoring

## Operational Relevance

Custom resources and controllers are core Kubernetes extensibility mechanisms.

The same architecture is used to build:

- database operators
- application platforms
- internal developer platforms
- infrastructure controllers
- backup controllers
- certificate automation
- policy automation
- managed service abstractions
- lifecycle automation
- GitOps-oriented control loops

The important pattern is:

    declare desired state
        |
        v
    reconcile continuously
        |
        v
    record observed state

rather than relying on one-time procedural provisioning.

## Final Outcome

The environment demonstrates a complete Kubernetes API-extension lifecycle:

    define a custom API
    validate resources at admission
    deploy a least-privilege controller
    create child resources
    continuously reconcile desired state
    repair manual drift
    expose observed status
    manage multiple custom resources
    establish ownership relationships
    use native garbage collection
    diagnose and correct controller/API integration failures

Final result:

    SUCCESS
