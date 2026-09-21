# Kubernetes RBAC Access Controls

## Overview

This implementation demonstrates Kubernetes authorization and workload identity controls using native Role-Based Access Control (RBAC).

The environment separates development, production, and testing workloads into independent namespaces and assigns different permissions to service accounts based on operational responsibility.

The implementation validates:

- Namespace-level access isolation
- Kubernetes service-account identities
- Roles and RoleBindings
- ClusterRoles and ClusterRoleBindings
- Least-privilege authorization
- Cross-namespace read-only access
- In-Pod Kubernetes API authorization
- Explicit allow and deny testing
- Exact resource-name restrictions
- Temporary privileged-access grant and revocation
- NetworkPolicy configuration
- Effective-permission auditing
- Automated RBAC validation

---

## Architecture

~~text
                         Kubernetes API Server
                                |
                                v
                        RBAC Authorization
                                |
              +-----------------+-----------------+
              |                 |                 |
              v                 v                 v
        development         production          testing
              |                 |                 |
              v                 v                 v
          dev-team           prod-team      readonly-user
       ServiceAccount      ServiceAccount    ServiceAccount
              |                 |                 |
              v                 v                 v
        dev-full-access   prod-limited-access  readonly-access
              |                 |                 |
              v                 v                 |
         RoleBinding         RoleBinding          |
                                                |
                                                v
                                         cluster-viewer
                                           ClusterRole
                                                |
                                                v
                                      ClusterRoleBinding
                                                |
                                                v
                                    Cross-Namespace Read
~~

---

## Environment

The Kubernetes environment was prepared using:

- Kubernetes v1.36
- kubeadm
- kubelet
- kubectl
- containerd 2.x
- CRI v1
- Flannel CNI

The container runtime was validated before control-plane initialization using:

~~bash
sudo crictl info
~~

This prevents Kubernetes from being initialized against an unusable CRI endpoint.

---

## Namespace Isolation

Three namespaces establish separate security boundaries:

~~text
development
production
testing
~~

### Development

Contains:

- `dev-app`
- `dev-app-service`
- `dev-team` service account

### Production

Contains:

- `prod-app`
- `prod-app-service`
- `prod-team` service account

### Testing

Provides an isolated namespace for the read-only identity.

---

## Service Account Identities

Dedicated service accounts were created instead of relying on the default identity:

~~text
development/dev-team
production/prod-team
testing/readonly-user
development/config-operator
~~

Identity Pods explicitly use these accounts through:

~~yaml
serviceAccountName: <service-account>
~~

Projected credentials were verified inside Pods under:

~~text
/var/run/secrets/kubernetes.io/serviceaccount/
~~

The mounted identity includes:

- Service-account token
- Namespace
- Cluster CA certificate

---

## Development Access Model

The `dev-team` identity is bound to the `dev-full-access` Role within the development namespace.

It can manage:

- Pods
- Pod logs
- Services
- ConfigMaps
- Secrets
- PersistentVolumeClaims
- Deployments
- ReplicaSets
- Ingresses

Expected authorization:

~~text
create pods in development             ALLOW
create configmaps in development       ALLOW
create deployments in development      ALLOW
delete deployments in development      ALLOW
list pods in production                DENY
~~

The namespace boundary prevents development credentials from implicitly accessing production resources.

---

## Production Access Model

The `prod-team` identity uses a restricted `prod-limited-access` Role.

Allowed capabilities include:

- Read Pods
- Read Pod logs
- Read Services
- Read ConfigMaps
- Read Deployments
- Read ReplicaSets
- Update Deployments
- Patch Deployments

Destructive and sensitive operations are excluded.

Expected authorization:

~~text
list pods in production                ALLOW
view deployments in production         ALLOW
patch deployments in production        ALLOW
create secrets in production           DENY
delete deployments in production       DENY
list development pods                  DENY
~~

This models a production operator with operational access without unrestricted administrative privilege.

---

## Read-Only Cluster Visibility

The `readonly-user` identity receives namespace-level read permissions in `testing` and cluster-wide visibility through the `cluster-viewer` ClusterRole.

Read-only cluster access includes:

- Namespaces
- Nodes
- Pods
- Services
- Deployments
- ReplicaSets

Expected behavior:

~~text
list namespaces                        ALLOW
list nodes                             ALLOW
list development pods                  ALLOW
create pods in testing                 DENY
create secrets in testing              DENY
~~

---

## RoleBindings and ClusterRoleBindings

Namespace Roles are assigned using:

~~text
dev-team-binding
prod-team-binding
readonly-binding
specific-resource-binding
~~

Cluster-wide visibility is assigned with:

~~text
cluster-viewer-binding
~~

RBAC object relationships:

~~text
Role
  -> namespace-scoped permissions

RoleBinding
  -> assigns permissions within a namespace

ClusterRole
  -> reusable or cluster-scoped permissions

ClusterRoleBinding
  -> grants ClusterRole permissions cluster-wide
~~

---

## In-Pod Authorization Validation

Authorization was tested from actual Pods using their mounted service-account credentials.

Identity Pods:

~~text
development/dev-pod
production/prod-pod
testing/readonly-pod
~~

Examples:

~~bash
kubectl exec -n development dev-pod -- \
  kubectl get pods -n development

kubectl exec -n production prod-pod -- \
  kubectl get deployments -n production

kubectl exec -n testing readonly-pod -- \
  kubectl get nodes
~~

Negative authorization tests were also executed from inside the Pods.

This validates the identity model actually used by Kubernetes workloads and automation.

---

## Automated Permission Testing

The reusable script:

~~text
scripts/test-permissions.sh
~~

tests both expected ALLOW and DENY outcomes.

### Development

~~text
List development Pods                 ALLOW
Create ConfigMap                      ALLOW
Create Deployment                     ALLOW
Read production Pods                  DENY
~~

### Production

~~text
List production Pods                  ALLOW
View production Deployments           ALLOW
Patch production Deployments          ALLOW
Create Secret                         DENY
Delete Deployment                     DENY
Read development Pods                 DENY
~~

### Read-Only

~~text
List testing Pods                     ALLOW
List namespaces                       ALLOW
List nodes                            ALLOW
View development Pods                 ALLOW
Create Pod                            DENY
Create Secret                         DENY
~~

Evidence is stored in:

~~text
rbac-permission-matrix.txt
kubectl-auth-matrix.txt
~~

---

## Exact Resource-Level Authorization

Kubernetes RBAC `resourceNames` requires exact resource names.

Patterns such as:

~~text
dev-app-*
~~

do not act as wildcards.

A dedicated `config-operator` service account demonstrates exact object-level authorization.

Allowed:

~~text
app-config
database-config
~~

Denied:

~~text
unrelated-config
~~

This demonstrates fine-grained authorization below the namespace level.

---

## Temporary Privileged Access

Temporary access is controlled through:

~~text
scripts/temporary-access.sh
~~

Supported operations:

~~bash
./scripts/temporary-access.sh grant
./scripts/temporary-access.sh revoke
~~

Granting access creates:

- `temp-admin` ServiceAccount
- `temp-admin-binding` RoleBinding

Revocation removes both resources.

Final auditing verifies that temporary privilege does not remain active.

---

## NetworkPolicy Integration

The development workload includes:

~~text
development-network-policy
~~

The policy targets Pods labeled:

~~text
app=dev-app
~~

and defines ingress, application egress, and DNS rules.

The Kubernetes API accepts and stores the NetworkPolicy.

Because the environment uses Flannel, this implementation does not claim runtime traffic enforcement unless the deployed CNI configuration actually provides NetworkPolicy enforcement.

---

## RBAC Auditing

Effective permissions are audited with:

~~bash
kubectl auth can-i --list
~~

Targeted authorization checks use:

~~bash
kubectl auth can-i <verb> <resource> \
  --as=system:serviceaccount:<namespace>:<service-account> \
  -n <namespace>
~~

The audit inventories:

- ServiceAccounts
- Roles
- RoleBindings
- ClusterRoles
- ClusterRoleBindings
- Effective permissions
- ALLOW decisions
- DENY decisions
- Temporary privilege state

---

## Access Matrix

The final access matrix compares the intended security policy against Kubernetes authorization decisions.

~~text
IDENTITY         SCOPE          ACTION   RESOURCE                     EXPECTED
dev-team         development    create   pods                         yes
dev-team         production     get      pods                         no
prod-team        production     list     pods                         yes
prod-team        production     patch    deployments                  yes
prod-team        production     delete   deployments                  no
prod-team        production     create   secrets                      no
readonly-user    cluster        list     nodes                        yes
readonly-user    development    list     pods                         yes
readonly-user    testing        create   pods                         no
config-operator  development    get      configmap/app-config         yes
config-operator  development    get      configmap/unrelated-config   no
~~

The validation fails when an actual authorization decision differs from the expected policy.

---

## Security Corrections

### Current Ingress API

Older Kubernetes examples may use:

~~text
apiGroups: ["extensions"]
~~

The current implementation uses:

~~text
apiGroups: ["networking.k8s.io"]
~~

for Ingress authorization.

### Resource Name Wildcards

RBAC does not provide wildcard expansion inside `resourceNames`.

Exact object names are used instead.

### Negative Security Testing

Security validation includes operations that must fail.

Examples:

- Development accessing production
- Production creating Secrets
- Production deleting Deployments
- Read-only identity creating Pods
- Read-only identity creating Secrets
- Resource-specific identity reading an unauthorized ConfigMap

Successful operations alone are not treated as sufficient proof of a correct authorization model.

---

## Evidence Files

~~text
namespace-baseline-evidence.txt
rbac-baseline-evidence.txt
service-account-identity-evidence.txt
rbac-permission-matrix.txt
kubectl-auth-matrix.txt
advanced-rbac-evidence.txt
rbac-audit-report.txt
rbac-access-matrix.txt
rbac-security-evidence.txt
~~

---

## Repository Structure

~~text
kubernetes-rbac-access-controls/
├── README.md
├── namespace-baseline-evidence.txt
├── rbac-baseline-evidence.txt
├── service-account-identity-evidence.txt
├── rbac-permission-matrix.txt
├── kubectl-auth-matrix.txt
├── advanced-rbac-evidence.txt
├── rbac-audit-report.txt
├── rbac-access-matrix.txt
├── rbac-security-evidence.txt
├── manifests/
│   ├── dev-app.yaml
│   ├── prod-app.yaml
│   ├── dev-role.yaml
│   ├── prod-role.yaml
│   ├── readonly-role.yaml
│   ├── dev-rolebinding.yaml
│   ├── prod-rolebinding.yaml
│   ├── readonly-rolebinding.yaml
│   ├── cluster-viewer-role.yaml
│   ├── cluster-viewer-binding.yaml
│   ├── dev-pod.yaml
│   ├── prod-pod.yaml
│   ├── readonly-pod.yaml
│   ├── specific-resource-role.yaml
│   ├── specific-resource-binding.yaml
│   └── network-policy.yaml
└── scripts/
    ├── test-permissions.sh
    ├── temporary-access.sh
    └── audit-permissions.sh
~~

---

## Skills Demonstrated

- Kubernetes RBAC
- ServiceAccounts
- Workload identity
- Roles
- RoleBindings
- ClusterRoles
- ClusterRoleBindings
- Least-privilege authorization
- Namespace isolation
- Kubernetes API authorization
- Identity impersonation testing
- Positive and negative security testing
- Exact-resource authorization
- Temporary privilege management
- Permission auditing
- NetworkPolicy configuration
- Multi-tenant access design
- Security evidence generation
- containerd CRI troubleshooting
- kubeadm administration

---

## Operational Relevance

These controls apply directly to:

- Multi-team Kubernetes clusters
- Platform engineering
- DevSecOps
- CI/CD workload identities
- Production namespace protection
- Developer self-service platforms
- AIOps infrastructure
- Security auditing
- Compliance controls
- Least-privilege access management

The implementation demonstrates not only how Kubernetes permissions are configured, but how security boundaries are tested, audited, and revoked when no longer required.
