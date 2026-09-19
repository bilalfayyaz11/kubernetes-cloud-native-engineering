# Kubernetes RBAC and Workload Identity

## Overview

This implementation demonstrates Kubernetes workload identity and access control using ServiceAccounts, Roles, RoleBindings, ClusterRoles, and ClusterRoleBindings.

The configuration applies the principle of least privilege by assigning different permissions to application, database, monitoring, and highly restricted identities.

Authorization is validated in two ways:

- declaratively with `kubectl auth can-i`
- at runtime through direct Kubernetes API requests using projected ServiceAccount tokens

The implementation also includes RBAC auditing, cross-namespace access validation, explicit token-mount controls, resource-specific authorization, and cleanup verification.

## Architecture

    access-control namespace
    |
    +-- webapp-service-account
    |      |
    |      +-- webapp-role
    |      |
    |      +-- webapp-rolebinding
    |
    +-- database-service-account
    |      |
    |      +-- database-role
    |      |
    |      +-- database-rolebinding
    |
    +-- minimal-service-account
    |      |
    |      +-- minimal-role
    |      |
    |      +-- minimal-rolebinding
    |
    +-- monitoring-service-account
           |
           +-- monitoring-readonly ClusterRole
           |
           +-- monitoring-readonly-binding ClusterRoleBinding

## Identity Model

Kubernetes ServiceAccounts provide workload identity.

They do not automatically grant permissions.

Permissions are granted separately through RBAC objects.

Identity format:

    system:serviceaccount:<namespace>:<serviceaccount>

Examples:

    system:serviceaccount:access-control:webapp-service-account
    system:serviceaccount:access-control:database-service-account
    system:serviceaccount:access-control:monitoring-service-account
    system:serviceaccount:access-control:minimal-service-account

## Namespace Isolation

Application-scoped access is isolated inside:

    access-control

A second namespace was used to validate cross-namespace monitoring visibility:

    monitoring-test

This separates namespace-scoped permissions from cluster-wide permissions.

## ServiceAccount Security

The custom ServiceAccounts disable automatic token mounting:

    automountServiceAccountToken: false

This reduces unnecessary credential exposure.

Only workloads that deliberately require Kubernetes API access explicitly enable token mounting at the Pod template level.

Example:

    serviceAccountName: webapp-service-account
    automountServiceAccountToken: true

This makes API credential exposure intentional rather than automatic.

## Web Application Identity

The web application identity receives read-only access to application-oriented resources.

Allowed:

    get/list/watch pods
    get/list services
    get/list/watch configmaps
    get/list/watch deployments

Denied:

    get secrets
    create pods

Authorization examples:

    kubectl auth can-i get pods \
      -n access-control \
      --as=system:serviceaccount:access-control:webapp-service-account

    kubectl auth can-i get secrets \
      -n access-control \
      --as=system:serviceaccount:access-control:webapp-service-account

Expected behavior:

    get pods     -> yes
    get secrets  -> no
    create pods  -> no

## Database Identity

The database-oriented identity uses a separate Role.

Allowed:

    get secrets
    get/list/watch persistentvolumeclaims
    get/list/watch pods
    get/list/watch statefulsets

Denied:

    get services
    create pods
    list secrets

The Role intentionally allows:

    get secrets

without granting:

    list secrets

This distinction prevents the identity from enumerating every Secret in the namespace.

## Named Secret Authorization

A non-sensitive test Secret was created to verify Kubernetes authorization semantics.

The database identity could retrieve:

    secret/rbac-demo-secret

but could not list the Secret collection.

Validation:

    kubectl auth can-i get secret/rbac-demo-secret \
      -n access-control \
      --as=system:serviceaccount:access-control:database-service-account

Expected:

    yes

Collection-level test:

    kubectl auth can-i list secrets \
      -n access-control \
      --as=system:serviceaccount:access-control:database-service-account

Expected:

    no

This demonstrates the important difference between Kubernetes `get` and `list` authorization verbs.

## RoleBindings

RoleBindings connect namespace-scoped permissions to ServiceAccounts.

Web application:

    webapp-service-account
             |
             v
    webapp-rolebinding
             |
             v
        webapp-role

Database identity:

    database-service-account
             |
             v
    database-rolebinding
             |
             v
        database-role

RoleBindings do not create permissions themselves.

They associate a subject with an existing Role or ClusterRole.

## Runtime Workload Identity

Test workloads explicitly use the ServiceAccounts.

Web application:

    serviceAccountName: webapp-service-account

Database test workload:

    serviceAccountName: database-service-account

The running Pod specifications were inspected to confirm that the expected ServiceAccount was attached.

## Projected ServiceAccount Tokens

For runtime API validation, token mounting was explicitly enabled on the test workloads.

Inside the Pod, Kubernetes exposes identity material under:

    /var/run/secrets/kubernetes.io/serviceaccount/

Important files include:

    token
    ca.crt
    namespace

The token authenticates the workload to the Kubernetes API.

RBAC then determines whether the requested action is authorized.

## Direct Kubernetes API Validation

Authorization was tested from inside the actual running Pods.

The API endpoint used was:

    https://kubernetes.default.svc

The Pod supplied:

    Authorization: Bearer <projected-token>

and validated the API server certificate using:

    /var/run/secrets/kubernetes.io/serviceaccount/ca.crt

## Web Application Runtime Results

Pod collection request:

    GET /api/v1/namespaces/access-control/pods

Result:

    HTTP 200

Secret collection request:

    GET /api/v1/namespaces/access-control/secrets

Result:

    HTTP 403

This proved that the actual workload identity could read Pods while Secret access was denied.

## Database Runtime Results

Named Secret request:

    GET /api/v1/namespaces/access-control/secrets/rbac-demo-secret

Result:

    HTTP 200

Secret collection request:

    GET /api/v1/namespaces/access-control/secrets

Result:

    HTTP 403

Service collection request:

    GET /api/v1/namespaces/access-control/services

Result:

    HTTP 403

This proves that precise access can be granted without broader namespace visibility.

## Cluster-Wide Monitoring Identity

A dedicated monitoring ServiceAccount is bound to a read-only ClusterRole.

ClusterRole:

    monitoring-readonly

ClusterRoleBinding:

    monitoring-readonly-binding

Allowed cluster-wide:

    get/list/watch pods
    get/list/watch services
    get/list/watch endpoints
    get/list/watch namespaces
    get/list/watch deployments
    get/list/watch replicasets
    get/list/watch statefulsets

Denied:

    create pods
    delete pods
    get secrets
    patch deployments

## Cross-Namespace Validation

The monitoring identity was tested against:

    access-control
    monitoring-test
    kube-system

Examples:

    kubectl auth can-i list pods \
      --all-namespaces \
      --as=system:serviceaccount:access-control:monitoring-service-account

Expected:

    yes

System namespace test:

    kubectl auth can-i get pods \
      -n kube-system \
      --as=system:serviceaccount:access-control:monitoring-service-account

Expected:

    yes

Write test:

    kubectl auth can-i create pods \
      -n access-control \
      --as=system:serviceaccount:access-control:monitoring-service-account

Expected:

    no

Secret test:

    kubectl auth can-i get secrets \
      -n access-control \
      --as=system:serviceaccount:access-control:monitoring-service-account

Expected:

    no

This demonstrates cluster-wide observability without cluster-wide write access.

## Resource-Specific Least Privilege

A highly restricted identity demonstrates the `resourceNames` RBAC feature.

The Role permits:

    get pod/restricted-target

but does not permit:

    list pods
    get unrelated pods
    create pods
    get secrets

Conceptually:

    resources:
      - pods

    resourceNames:
      - restricted-target

    verbs:
      - get

This limits access to one named Kubernetes object.

## Important resourceNames Behavior

A Role using `resourceNames` can authorize:

    get pod/restricted-target

while this may still return:

    no

for:

    get pods

because the latter does not identify the specific resource name.

Similarly:

    list pods

remains denied unless explicitly granted.

This makes `resourceNames` useful for highly constrained object-level access.

## Authorization Matrix

The final authorization model was:

### Web Application

    get pods          yes
    list pods         yes
    create pods       no
    get services      yes
    get configmaps    yes
    get secrets       no

### Database

    get pods          yes
    list pods         yes
    create pods       no
    get services      no
    get configmaps    no
    get secrets       yes

Additional Secret behavior:

    get named secret  yes
    list secrets      no

### Monitoring

    get pods          yes
    list pods         yes
    create pods       no
    get services      yes
    get configmaps    no
    get secrets       no

The monitoring identity additionally has read access across namespaces.

### Minimal Identity

General checks:

    get pods          no
    list pods         no
    create pods       no
    get services      no
    get configmaps    no
    get secrets       no

Specific-resource check:

    get pod/restricted-target  yes

This demonstrates object-level authorization rather than general Pod access.

## Permission Testing

A reusable authorization script executes `kubectl auth can-i` checks for each identity.

This provides a fast RBAC regression test.

Typical command:

    kubectl auth can-i <verb> <resource> \
      -n access-control \
      --as=system:serviceaccount:access-control:<identity>

Examples:

    kubectl auth can-i get pods ...

    kubectl auth can-i create pods ...

    kubectl auth can-i get secrets ...

## RBAC Audit

The audit workflow inventories:

- ServiceAccounts
- token automount settings
- Roles
- Role rules
- RoleBindings
- ClusterRoles
- ClusterRoleBindings
- authorization results

Run:

    ./audit-rbac.sh

The resulting evidence can be captured with:

    ./audit-rbac.sh | tee rbac-audit-report-final.txt

## Evidence Files

The implementation preserves authorization and security evidence including:

    final-permission-matrix.txt
    rbac-audit-report-final.txt
    webapp-permissions.txt
    database-permissions.txt
    monitoring-permissions.txt
    minimal-permissions.txt
    rbac-resource-inventory.txt
    rbac-tree.txt

These files document the evaluated authorization state before runtime cleanup.

## Troubleshooting

### ServiceAccount Has No Access

A ServiceAccount only provides identity.

Check its RoleBinding:

    kubectl describe rolebinding webapp-rolebinding \
      -n access-control

Verify:

- subject kind is ServiceAccount
- ServiceAccount name is correct
- namespace is correct
- referenced Role exists

### Pod Cannot Reach Kubernetes API

Check whether the workload has a projected token:

    kubectl exec <pod> \
      -n access-control -- \
      ls /var/run/secrets/kubernetes.io/serviceaccount/

If the ServiceAccount defaults to:

    automountServiceAccountToken: false

then the Pod must explicitly enable it when API access is required.

### 403 Forbidden

HTTP 403 generally means:

- authentication succeeded
- Kubernetes recognized the identity
- RBAC denied the requested action

Confirm using:

    kubectl auth can-i

with the exact workload identity.

### get vs list Confusion

Requesting:

    /api/v1/namespaces/access-control/secrets

is a collection request and requires:

    list

Requesting:

    /api/v1/namespaces/access-control/secrets/<name>

requires:

    get

These permissions are independent.

A Role may permit one while denying the other.

### ClusterRole Appears Ineffective

Inspect the binding:

    kubectl describe clusterrolebinding monitoring-readonly-binding

Verify that the binding references:

    kind: ClusterRole

and contains the correct ServiceAccount subject and namespace.

### Role vs ClusterRole

A Role is namespace-scoped.

A ClusterRole defines permissions that can be used across namespaces or for cluster-scoped resources.

A ClusterRoleBinding grants the referenced ClusterRole permissions cluster-wide to its subjects.

## Security Practices Demonstrated

### Least Privilege

Only required verbs and resources are granted.

### Separate Identities

Web, database, monitoring, and minimal workloads do not share one privileged ServiceAccount.

### Explicit Token Mounting

Automatic token mounting is disabled by default for custom identities.

### Read vs Write Separation

Monitoring receives observation privileges without mutation privileges.

### Secret Enumeration Prevention

The database identity can retrieve a required named Secret without receiving permission to enumerate all Secrets.

### Resource-Level Restriction

`resourceNames` restricts one identity to one specific Pod.

### Positive and Negative Testing

Security controls are validated by proving both permitted and forbidden behavior.

## Cleanup

Runtime resources can be removed after validation while preserving configuration and evidence.

Typical cleanup includes:

    kubectl delete deployment \
      webapp-deployment database-deployment \
      -n access-control

    kubectl delete clusterrolebinding \
      monitoring-readonly-binding

    kubectl delete clusterrole \
      monitoring-readonly

    kubectl delete namespace \
      monitoring-test access-control

Cleanup verification confirms that no custom runtime access-control resources remain.

## Technologies

- Kubernetes
- K3s
- kubectl
- ServiceAccounts
- Roles
- RoleBindings
- ClusterRoles
- ClusterRoleBindings
- projected ServiceAccount tokens
- Kubernetes API
- YAML
- Bash
- curl

## Engineering Skills Demonstrated

- Kubernetes workload identity
- namespace-scoped RBAC
- cluster-wide RBAC
- principle of least privilege
- ServiceAccount token management
- Role and RoleBinding design
- ClusterRole and ClusterRoleBinding design
- resource-level authorization
- Kubernetes API authentication
- runtime authorization verification
- HTTP 200 vs 403 security validation
- access-control troubleshooting
- RBAC auditing
- security evidence generation
- credential-exposure reduction
- cross-namespace authorization

## Operational Use Case

A real Kubernetes platform commonly requires multiple workload identities with different trust boundaries.

For example:

    frontend
       |
       +--> read application configuration

    database controller
       |
       +--> retrieve one required credential

    monitoring agent
       |
       +--> read operational resources cluster-wide

    restricted automation
       |
       +--> access one explicitly named resource

RBAC allows each identity to receive only the permissions required for its responsibility.

## Key Takeaways

- ServiceAccounts identify workloads; they do not automatically grant permissions.
- Roles define namespace-scoped permissions.
- RoleBindings connect identities to Roles.
- ClusterRoles can define cross-namespace permissions.
- ClusterRoleBindings grant ClusterRole permissions cluster-wide.
- Disable unnecessary automatic ServiceAccount token mounting.
- Grant only required verbs.
- Treat `get` and `list` as separate privileges.
- Avoid broad Secret enumeration where named-resource access is sufficient.
- Use `resourceNames` for highly constrained object access.
- Test denied behavior as deliberately as allowed behavior.
- Validate authorization from the actual workload identity.
- Audit RBAC configuration continuously rather than assuming bindings are correct.
