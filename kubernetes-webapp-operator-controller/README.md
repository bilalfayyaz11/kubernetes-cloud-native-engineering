# Kubernetes WebApp Custom API and Reconciliation Controller

## What This Does

This implementation extends the Kubernetes API with a custom `WebApp` resource and introduces a Python-based reconciliation controller that converts declarative application specifications into managed Kubernetes Deployments.

Users define application intent through a namespaced custom resource containing replica count, container image, application port, and resource requests. The controller continuously compares this desired state with the actual cluster state and automatically creates or updates Deployments until both converge.

The implementation also exposes operational status through the CRD status subresource, applies least-privilege RBAC, validates custom-resource input, supports multiple resources simultaneously, and demonstrates troubleshooting patterns used by production Kubernetes controllers.

## Architecture

    User / Platform Engineer
             |
             | kubectl apply
             v
    +---------------------------+
    | WebApp Custom Resource    |
    | example.com/v1            |
    |                           |
    | replicas                  |
    | image                     |
    | port                      |
    | resources                 |
    +-------------+-------------+
                  |
                  v
    +---------------------------+
    | Kubernetes API Server     |
    |                           |
    | CRD: webapps.example.com  |
    | Validation Schema         |
    | Status Subresource        |
    +-------------+-------------+
                  |
                  | list / reconcile
                  v
    +---------------------------+
    | WebApp Controller         |
    | Python Kubernetes Client  |
    |                           |
    | ServiceAccount            |
    | ClusterRole               |
    | ClusterRoleBinding        |
    +-------------+-------------+
                  |
                  | create / patch
                  v
    +---------------------------+
    | Managed Deployment        |
    | my-webapp-deployment      |
    +-------------+-------------+
                  |
          +-------+-------+
          |       |       |
          v       v       v
        Pod     Pod     Pod
          |
          v
    +---------------------------+
    | ClusterIP Service         |
    | my-webapp-service         |
    +---------------------------+

The reconciliation loop also writes observed readiness information back into:

    WebApp.status.availableReplicas
    WebApp.status.conditions

## Prerequisites

- Linux environment
- Kubernetes cluster
- kubectl
- Valid Kubernetes context
- Permission to create CRDs
- Permission to create RBAC resources
- Internet access for container image pulls
- Python-compatible container runtime in Kubernetes

Validate the environment with:

    kubectl cluster-info
    kubectl get nodes
    kubectl config current-context

Verify authorization:

    kubectl auth can-i create \
      customresourcedefinitions.apiextensions.k8s.io

    kubectl auth can-i create \
      clusterroles.rbac.authorization.k8s.io

    kubectl auth can-i create \
      clusterrolebindings.rbac.authorization.k8s.io

For a lightweight local or cloud VM environment, K3s can provide the Kubernetes control plane:

    curl -sfL https://get.k3s.io | \
      INSTALL_K3S_EXEC="server --disable=traefik" sh -

    mkdir -p "$HOME/.kube"

    sudo cp /etc/rancher/k3s/k3s.yaml \
      "$HOME/.kube/config"

    sudo chown "$(id -u):$(id -g)" \
      "$HOME/.kube/config"

    chmod 600 "$HOME/.kube/config"

    export KUBECONFIG="$HOME/.kube/config"

## Setup & Installation

Apply the CustomResourceDefinition:

    kubectl apply -f webapp-crd.yaml

Wait for the API extension to become available:

    kubectl wait \
      --for=condition=Established \
      crd/webapps.example.com \
      --timeout=120s

Verify API discovery:

    kubectl api-resources | grep webapps

Apply controller RBAC:

    kubectl apply -f webapp-operator-rbac.yaml

Verify controller authorization:

    kubectl auth can-i \
      --as=system:serviceaccount:default:webapp-operator \
      list webapps.example.com

    kubectl auth can-i \
      --as=system:serviceaccount:default:webapp-operator \
      create deployments.apps

    kubectl auth can-i \
      --as=system:serviceaccount:default:webapp-operator \
      patch webapps.example.com \
      --subresource=status

Deploy the controller:

    kubectl apply -f webapp-operator-deployment.yaml

Wait for it to become ready:

    kubectl rollout status \
      deployment/webapp-operator \
      --timeout=300s

## How to Reproduce

### 1. Install the Custom API

Apply:

    kubectl apply -f webapp-crd.yaml

The CRD registers:

    Group: example.com
    Version: v1
    Kind: WebApp
    Plural: webapps
    Short name: wa
    Scope: Namespaced

The schema validates:

    replicas: 1-10
    image: non-empty string
    port: 1-65535
    resources.cpu
    resources.memory

The CRD also enables:

    /status

for controller-managed observed state.

### 2. Validate Schema Enforcement

An invalid resource such as:

    replicas: 50

is rejected by the Kubernetes API before it reaches the controller.

This keeps invalid desired state out of the reconciliation loop.

### 3. Create a WebApp Resource

Apply:

    kubectl apply -f sample-webapp.yaml

Inspect it:

    kubectl get webapps
    kubectl get wa
    kubectl describe webapp my-webapp

Example desired state:

    replicas: 3
    image: nginx:1.29-alpine
    port: 80
    cpu: 100m
    memory: 128Mi

At this stage the custom resource exists independently of a Deployment.

### 4. Deploy the Reconciliation Controller

Apply RBAC:

    kubectl apply -f webapp-operator-rbac.yaml

Deploy the controller:

    kubectl apply -f webapp-operator-deployment.yaml

Inspect controller health:

    kubectl get pods \
      -l app=webapp-operator

Inspect reconciliation activity:

    kubectl logs \
      -l app=webapp-operator

### 5. Verify Automatic Deployment Creation

The controller observes:

    WebApp/my-webapp

and automatically creates:

    Deployment/my-webapp-deployment

Verify:

    kubectl get deployment my-webapp-deployment

    kubectl get pods \
      -l app=my-webapp

No Deployment manifest is manually applied for the managed application.

The controller translates the custom resource into native Kubernetes resources.

### 6. Verify Full Desired-State Reconciliation

Modify the custom resource:

    kubectl patch webapp my-webapp \
      --type='merge' \
      -p='{
        "spec":{
          "replicas":5,
          "image":"nginx:1.29",
          "port":8080,
          "resources":{
            "cpu":"150m",
            "memory":"192Mi"
          }
        }
      }'

The controller detects drift and patches the managed Deployment.

Verify:

    kubectl get deployment my-webapp-deployment \
      -o yaml

The reconciliation logic manages:

    replica count
    container image
    container port
    CPU requests
    memory requests
    controller ownership labels

### 7. Verify Scale Reconciliation

Scale through the custom API:

    kubectl patch webapp my-webapp \
      --type='merge' \
      -p='{"spec":{"replicas":2}}'

The controller automatically updates:

    Deployment/my-webapp-deployment

Verify:

    kubectl get deployment my-webapp-deployment
    kubectl get pods -l app=my-webapp

This demonstrates the declarative control-loop model: users modify desired state rather than directly operating the underlying Deployment.

### 8. Verify Status Reporting

Inspect:

    kubectl get webapp my-webapp -o yaml

The controller writes observed state into:

    status:
      availableReplicas:
      conditions:

The status condition communicates whether the managed Deployment currently has ready replicas.

A focused status query can be performed with:

    kubectl get webapp my-webapp \
      -o jsonpath='{.status}' | \
      python3 -m json.tool

### 9. Manage Multiple Custom Resources

Apply:

    kubectl apply -f second-webapp.yaml

The controller independently creates:

    second-webapp-deployment

while continuing to reconcile:

    my-webapp-deployment

Verify all custom resources:

    kubectl get webapps

Verify controller-managed Deployments:

    kubectl get deployments \
      -l managed-by=webapp-operator

Verify managed pods:

    kubectl get pods \
      -l managed-by=webapp-operator

This demonstrates that one controller instance can reconcile multiple resource instances.

### 10. Test Deletion Behavior

Delete:

    kubectl delete webapp second-webapp

The current controller intentionally demonstrates a lifecycle limitation:

    second-webapp-deployment

can remain after its custom resource is removed.

This occurs because the controller does not currently implement:

    ownerReferences
    garbage-collection ownership
    finalizers
    explicit deletion reconciliation

The remaining Deployment can be removed manually:

    kubectl delete deployment second-webapp-deployment

A production controller should implement ownership or finalization semantics.

### 11. Create Application Service Access

Apply:

    kubectl apply -f my-webapp-service.yaml

Inspect:

    kubectl get service my-webapp-service

Inspect modern Kubernetes service backends:

    kubectl get endpointslice \
      -l kubernetes.io/service-name=my-webapp-service

The service routes traffic to pods carrying:

    app=my-webapp

### 12. Test In-Cluster Connectivity

Run a temporary client:

    kubectl run webapp-debug \
      --image=curlimages/curl:8.12.1 \
      --restart=Never \
      --command -- sleep 3600

Verify service DNS:

    kubectl exec webapp-debug -- \
      nslookup \
      my-webapp-service.default.svc.cluster.local

Verify HTTP connectivity:

    kubectl exec webapp-debug -- \
      curl \
      -sS \
      http://my-webapp-service.default.svc.cluster.local

Remove the temporary client:

    kubectl delete pod webapp-debug

## Controller Behavior

The reconciliation controller continuously performs the following workflow:

    1. Query all WebApp resources.
    2. Read each resource's desired specification.
    3. Check whether a corresponding Deployment exists.
    4. Create the Deployment when absent.
    5. Compare the existing Deployment against desired state.
    6. Patch replicas, image, port, resource requests, or labels when drift exists.
    7. Read observed Deployment readiness.
    8. Update the WebApp status subresource.
    9. Sleep briefly and repeat.

This represents a simplified implementation of the Kubernetes controller reconciliation pattern.

## RBAC Model

The controller uses a dedicated ServiceAccount:

    webapp-operator

It receives permissions only for the APIs required by its reconciliation logic.

Native resources:

    deployments.apps

Allowed operations:

    get
    list
    watch
    create
    update
    patch
    delete

Custom resources:

    webapps.example.com

Allowed operations:

    get
    list
    watch

Status subresource:

    webapps.example.com/status

Allowed operations:

    get
    update
    patch

This avoids giving the controller unrestricted cluster-admin privileges.

## Tools Used

- Kubernetes
- K3s
- kubectl
- CustomResourceDefinition
- Kubernetes API Extensions
- Python 3
- Kubernetes Python Client
- Deployment API
- ServiceAccount
- ClusterRole
- ClusterRoleBinding
- Status Subresources
- OpenAPI v3 CRD Validation
- ClusterIP Service
- EndpointSlice
- CoreDNS
- curl
- YAML

## Key Skills Demonstrated

- Extending the Kubernetes API with CustomResourceDefinitions
- Designing custom declarative resource schemas
- Implementing OpenAPI validation for custom resources
- Enabling and updating CRD status subresources
- Building Kubernetes reconciliation controllers
- Translating custom desired state into native resources
- Implementing continuous drift reconciliation
- Automating Deployment creation and modification
- Managing multiple custom-resource instances
- Applying least-privilege Kubernetes RBAC
- Using ServiceAccounts for workload identity
- Debugging authorization and subresource access
- Inspecting controller logs and cluster events
- Validating Kubernetes service discovery
- Testing application connectivity through ClusterIP Services
- Identifying lifecycle ownership and garbage-collection limitations

## Real-World Use Case

This pattern is useful when a platform team wants to expose a higher-level internal API instead of requiring application teams to directly manage many low-level Kubernetes manifests. A database platform could expose a `Database` resource, an AI platform could expose a `ModelServing` resource, or an internal developer platform could expose an `Application` resource. Controllers then encode organizational operational knowledge and automatically translate those resources into Deployments, Services, storage, policies, monitoring configuration, or cloud infrastructure.

## Lessons Learned

- CRDs turn Kubernetes into an extensible API platform rather than only a container orchestrator.
- A custom resource alone does not perform automation; a reconciliation controller gives the resource operational meaning.
- Status subresources should be explicitly enabled when a controller writes observed state back to a custom resource.
- Controller RBAC should grant only permissions required by reconciliation logic.
- Desired-state reconciliation must handle more than initial resource creation; configuration drift also needs to be corrected.
- Resource deletion requires deliberate ownership semantics through ownerReferences, finalizers, or deletion reconciliation.
- Operator behavior should be tested by changing the custom resource rather than directly editing resources managed by the controller.

## Troubleshooting Log

### Kubernetes Client Present but No Cluster

The fresh environment contained kubectl but no active Kubernetes context or API server.

Resolution:

- Installed K3s.
- Configured the user kubeconfig.
- Verified node readiness and API discovery before creating CRDs.

### Local pip Missing

Python was installed on the VM, but pip was unavailable.

Resolution:

- No host-level Python dependency installation was required.
- The controller runs inside a Python container.
- Kubernetes Python dependencies are installed inside the controller container.

### Status Subresource Missing From Original CRD Design

The custom resource schema contained a status field, while the controller attempted to use the Kubernetes status API.

Without explicit status-subresource configuration, this design is incomplete.

Resolution:

    subresources:
      status: {}

was added to the CRD.

### RBAC Status Verification Syntax

An initial permission check attempted to address the status resource directly and returned:

    no

The ClusterRole itself correctly allowed:

    webapps/status

Resolution:

Used kubectl subresource-aware authorization verification:

    kubectl auth can-i \
      --as=system:serviceaccount:default:webapp-operator \
      patch webapps.example.com \
      --subresource=status

The permission returned:

    yes

### Incomplete Desired-State Reconciliation

A minimal controller implementation that only changes replica count does not fully enforce the custom-resource specification.

Resolution:

The controller was extended to reconcile:

    replicas
    image
    port
    CPU requests
    memory requests
    pod labels

### Missing Managed Pod Label

Operational troubleshooting relies on being able to identify controller-managed workloads.

Resolution:

The controller applies:

    managed-by: webapp-operator

to both the Deployment and the Deployment pod template.

This enables:

    kubectl get pods \
      -l managed-by=webapp-operator

### Custom Resource Deletion Leaves Deployment

Deleting a WebApp resource did not automatically remove its corresponding Deployment.

Cause:

The simplified controller does not define:

    ownerReferences
    finalizers
    explicit deletion handling

Resolution during validation:

- Confirmed the orphaned Deployment behavior.
- Removed it manually.
- Documented ownership handling as the next production-hardening requirement.

## Production Hardening

A production-grade implementation should additionally introduce:

- OwnerReferences for automatic garbage collection
- Finalizers for controlled teardown
- Event-driven watches instead of periodic polling
- Leader election for highly available controllers
- Controller health and readiness endpoints
- Structured logging
- Kubernetes Events
- Prometheus metrics
- Retry and exponential backoff
- Admission validation where appropriate
- CRD version migration strategy
- Defaulting and conversion webhooks
- Container image built specifically for the controller
- Dependency pinning through a requirements file
- Image vulnerability scanning
- Pod security configuration
- NetworkPolicies
- Automated controller tests
- Reconciliation unit tests
- Integration tests
- GitOps-based release management
