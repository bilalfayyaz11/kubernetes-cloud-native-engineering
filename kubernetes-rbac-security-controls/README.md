# Kubernetes RBAC and Security Controls

## What This Does

This implementation builds and validates a Kubernetes security model based on Service Accounts, namespace-scoped Role-Based Access Control, cluster-level administrative permissions, ResourceQuota enforcement, and NetworkPolicy definitions.

Three application identities were created with distinct privilege levels: developer, viewer, and administrator. Their permissions were validated using isolated token-authenticated kubeconfigs to ensure requests were evaluated using the intended Service Account identities rather than the administrator credentials from the default Minikube kubeconfig.

The environment also applies namespace-level resource governance and network access policies, demonstrating how Kubernetes combines authentication, authorization, and policy controls to protect workloads in shared clusters.

## Architecture

~~text
┌───────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                       │
│                                                               │
│  ┌──────────────── Authentication ─────────────────────────┐  │
│  │                                                        │  │
│  │  developer-sa     viewer-sa          admin-sa          │  │
│  │       │                │                  │             │  │
│  └───────┼────────────────┼──────────────────┼─────────────┘  │
│          │                │                  │                │
│          ▼                ▼                  ▼                │
│  ┌────────────────── Authorization / RBAC ────────────────┐  │
│  │                                                        │  │
│  │ developer-role     viewer-role      cluster-admin      │  │
│  │ Read / Write       Read Only        Cluster Wide       │  │
│  │       │                │                  │             │  │
│  │ RoleBinding        RoleBinding     ClusterRoleBinding  │  │
│  └───────┬────────────────┬──────────────────┬─────────────┘  │
│          │                │                  │                │
│          └────────────────┴──────────────────┘                │
│                           │                                   │
│                           ▼                                   │
│                 security-lab Namespace                        │
│                           │                                   │
│       ┌───────────────────┼──────────────────┐                │
│       │                   │                  │                │
│       ▼                   ▼                  ▼                │
│   test-app           ResourceQuota      NetworkPolicy         │
│   Deployment          Enforcement        Controls             │
│                                                               │
│  Resource Governance:                                        │
│  ├── CPU requests / limits                                   │
│  ├── Memory requests / limits                                │
│  ├── Pod count                                               │
│  ├── Service count                                           │
│  └── ConfigMap count                                         │
└───────────────────────────────────────────────────────────────┘
~~

## Prerequisites

- Linux host
- Docker
- Minikube
- kubectl
- Kubernetes cluster with RBAC enabled
- Administrative Kubernetes credentials for initial configuration
- Kubernetes API access
- Support for Service Account token generation
- NetworkPolicy API support
- ResourceQuota admission support

## Setup & Installation

### Start Minikube

~~bash
minikube start \
  --driver=docker \
  --cpus=2 \
  --memory=3072
~~

Verify the cluster:

~~bash
minikube status
kubectl cluster-info
kubectl get nodes
~~

### Create the Security Namespace

~~bash
kubectl create namespace security-lab
kubectl config set-context --current --namespace=security-lab
~~

## How to Reproduce

### 1. Create Service Accounts

~~bash
kubectl create serviceaccount developer-sa -n security-lab
kubectl create serviceaccount viewer-sa -n security-lab
kubectl create serviceaccount admin-sa -n security-lab
~~

Verify:

~~bash
kubectl get serviceaccounts -n security-lab
~~

### 2. Create the Developer Role

~~yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: security-lab
  name: developer-role
rules:
- apiGroups: [""]
  resources:
  - pods
  - services
  - configmaps
  - secrets
  verbs:
  - get
  - list
  - create
  - update
  - patch
  - delete
- apiGroups: ["apps"]
  resources:
  - deployments
  - replicasets
  verbs:
  - get
  - list
  - create
  - update
  - patch
  - delete
~~

Apply:

~~bash
kubectl apply -f developer-role.yaml
~~

### 3. Create the Viewer Role

~~yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: security-lab
  name: viewer-role
rules:
- apiGroups: [""]
  resources:
  - pods
  - services
  - configmaps
  verbs:
  - get
  - list
- apiGroups: ["apps"]
  resources:
  - deployments
  - replicasets
  verbs:
  - get
  - list
~~

Apply:

~~bash
kubectl apply -f viewer-role.yaml
~~

### 4. Bind Roles to Service Accounts

Developer:

~~yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: security-lab
subjects:
- kind: ServiceAccount
  name: developer-sa
  namespace: security-lab
roleRef:
  kind: Role
  name: developer-role
  apiGroup: rbac.authorization.k8s.io
~~

Viewer:

~~yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: viewer-binding
  namespace: security-lab
subjects:
- kind: ServiceAccount
  name: viewer-sa
  namespace: security-lab
roleRef:
  kind: Role
  name: viewer-role
  apiGroup: rbac.authorization.k8s.io
~~

Apply:

~~bash
kubectl apply -f developer-rolebinding.yaml
kubectl apply -f viewer-rolebinding.yaml
~~

### 5. Configure Administrative Access

~~yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-binding
subjects:
- kind: ServiceAccount
  name: admin-sa
  namespace: security-lab
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
~~

Apply:

~~bash
kubectl apply -f admin-clusterrolebinding.yaml
~~

### 6. Validate Authorization

Kubernetes impersonation provides a fast server-side authorization check:

~~bash
kubectl auth can-i get pods \
  --as=system:serviceaccount:security-lab:viewer-sa \
  -n security-lab

kubectl auth can-i create configmaps \
  --as=system:serviceaccount:security-lab:viewer-sa \
  -n security-lab
~~

Expected:

~~text
yes
no
~~

### 7. Validate Real Service Account Authentication

Create temporary Service Account tokens:

~~bash
DEVELOPER_TOKEN=$(kubectl create token developer-sa -n security-lab)
VIEWER_TOKEN=$(kubectl create token viewer-sa -n security-lab)
ADMIN_TOKEN=$(kubectl create token admin-sa -n security-lab)
~~

Build isolated kubeconfigs so no administrator client certificate can override the Service Account identity.

Example viewer configuration:

~~bash
SERVER=$(kubectl config view --minify \
  -o jsonpath='{.clusters[0].cluster.server}')

CA_FILE=$(kubectl config view --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority}')

kubectl config \
  --kubeconfig=/tmp/viewer.kubeconfig \
  set-cluster minikube \
  --server="$SERVER" \
  --certificate-authority="$CA_FILE" \
  --embed-certs=true

kubectl config \
  --kubeconfig=/tmp/viewer.kubeconfig \
  set-credentials viewer-sa \
  --token="$VIEWER_TOKEN"

kubectl config \
  --kubeconfig=/tmp/viewer.kubeconfig \
  set-context viewer \
  --cluster=minikube \
  --user=viewer-sa \
  --namespace=security-lab

kubectl config \
  --kubeconfig=/tmp/viewer.kubeconfig \
  use-context viewer
~~

Confirm identity:

~~bash
kubectl \
  --kubeconfig=/tmp/viewer.kubeconfig \
  auth whoami
~~

Expected identity:

~~text
system:serviceaccount:security-lab:viewer-sa
~~

Test permissions:

~~bash
kubectl \
  --kubeconfig=/tmp/viewer.kubeconfig \
  auth can-i get pods

kubectl \
  --kubeconfig=/tmp/viewer.kubeconfig \
  auth can-i create configmaps

kubectl \
  --kubeconfig=/tmp/viewer.kubeconfig \
  auth can-i delete pods
~~

Expected:

~~text
yes
no
no
~~

### 8. Configure ResourceQuota

~~yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: security-lab-quota
  namespace: security-lab
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "10"
    services: "5"
    configmaps: "10"
~~

Apply:

~~bash
kubectl apply -f resource-quota.yaml
~~

Verify enforcement and current consumption:

~~bash
kubectl get resourcequota -n security-lab

kubectl describe \
  resourcequota security-lab-quota \
  -n security-lab
~~

The validated environment tracked CPU, memory, Pods, Services, and ConfigMaps against their configured namespace limits.

### 9. Configure Network Policies

~~yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: security-lab
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-test-app-ingress
  namespace: security-lab
spec:
  podSelector:
    matchLabels:
      app: test-app
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          access: allowed
    ports:
    - protocol: TCP
      port: 80
~~

Apply:

~~bash
kubectl apply -f network-policy.yaml

kubectl get networkpolicy -n security-lab
~~

NetworkPolicy resources require a CNI implementation that supports policy enforcement. Kubernetes accepts and stores the policy resources independently of whether the underlying CNI enforces packet filtering.

### 10. Final Authorization Matrix

Developer:

~~bash
kubectl \
  --kubeconfig=/tmp/developer.kubeconfig \
  auth can-i create configmaps
~~

Expected:

~~text
yes
~~

Viewer:

~~bash
kubectl \
  --kubeconfig=/tmp/viewer.kubeconfig \
  auth can-i create configmaps
~~

Expected:

~~text
no
~~

Admin:

~~bash
kubectl \
  --kubeconfig=/tmp/admin.kubeconfig \
  auth can-i '*' '*' --all-namespaces
~~

Expected:

~~text
yes
~~

## Tools Used

- Kubernetes
- Minikube
- kubectl
- Docker
- Kubernetes Service Accounts
- RBAC
- Roles
- RoleBindings
- ClusterRoles
- ClusterRoleBindings
- ResourceQuota
- NetworkPolicy
- Service Account tokens
- kubeconfig
- Kubernetes authorization API
- Kubernetes admission controls

## Key Skills Demonstrated

- Implementing Kubernetes least-privilege access
- Designing namespace-scoped RBAC policies
- Creating workload identities with Service Accounts
- Separating developer, viewer, and administrator privileges
- Testing Kubernetes authorization with `kubectl auth can-i`
- Validating real Service Account authentication
- Building isolated token-based kubeconfigs
- Troubleshooting credential precedence in kubectl
- Implementing namespace resource governance
- Applying CPU, memory, Pod, Service, and ConfigMap quotas
- Defining workload communication policies
- Distinguishing Kubernetes policy objects from CNI enforcement
- Troubleshooting Kubernetes API connectivity and authentication

## Real-World Use Case

This security model applies to multi-team Kubernetes environments where developers require controlled write access, auditors or support users require read-only access, and platform administrators require broader cluster permissions. Resource quotas reduce the risk of namespace-level resource exhaustion, while network policies define intended communication boundaries between workloads. Together, these mechanisms support least privilege, workload isolation, multi-tenancy, and operational governance.

## Lessons Learned

- Kubernetes authorization tests are only trustworthy when the authenticated identity is explicitly verified.
- Supplying a bearer token to kubectl does not automatically guarantee the expected identity when an existing kubeconfig also contains client-certificate credentials.
- Isolated kubeconfigs provide a reliable way to validate Service Account authentication independently from administrator credentials.
- Namespace-scoped Roles are preferable to broad cluster permissions when applications only require access to specific resources.
- ResourceQuota admission can prevent workloads from consuming resources beyond defined namespace limits.
- NetworkPolicy objects require compatible CNI enforcement; successful object creation alone does not prove traffic filtering.

## Troubleshooting Log

### kubectl requests authenticated as the wrong identity

Initial Service Account token tests unexpectedly allowed viewer write operations.

Identity inspection showed:

~~text
Username: minikube-user
Groups: [system:masters system:authenticated]
~~

The request was still presenting the administrator client certificate from the existing Minikube kubeconfig.

Resolution:

Separate token-only kubeconfig files were created for each Service Account.

After isolation, the viewer identity became:

~~text
system:serviceaccount:security-lab:viewer-sa
~~

The expected authorization behavior was then confirmed:

~~text
get pods:          yes
create configmaps: no
delete pods:       no
~~

### Kubernetes API became unreachable

kubectl temporarily returned:

~~text
dial tcp 192.168.49.2:8443: connect: no route to host
~~

The commands had accidentally been executed from the local workstation rather than the remote Kubernetes host.

Resolution:

Execution returned to the correct Minikube host and cluster connectivity was validated using:

~~bash
minikube status
kubectl cluster-info
kubectl get nodes
~~

### ResourceQuota and NetworkPolicy resources were missing

After the interrupted execution flow, the expected security objects were absent from the namespace.

Resolution:

The ResourceQuota and NetworkPolicy manifests were reapplied and verified explicitly.

~~bash
kubectl get resourcequota -n security-lab
kubectl get networkpolicy -n security-lab
~~

### Malformed NetworkPolicy manifest

The original policy definition contained invalid YAML structure.

Resolution:

The policies were rebuilt as two valid Kubernetes NetworkPolicy documents separated using `---`.

### NetworkPolicy enforcement dependency

An unauthorized client was initially able to reach the workload despite policy definitions being discussed.

Further inspection showed that the policies were not present during that test. After recreation, the policy objects were verified successfully.

Actual traffic enforcement remains dependent on the CNI implementation used by the cluster, so policy presence and CNI enforcement must be validated independently.

### Unreliable API server Pod discovery

A hostname-derived API server Pod name was not reliable in Minikube.

Resolution:

The control-plane Pod was discovered dynamically using Kubernetes labels rather than assuming its name.

## Security Principles Demonstrated

The implementation demonstrates several production security principles:

- Least privilege
- Explicit workload identity
- Namespace isolation
- Role separation
- Authentication verification
- Authorization enforcement
- Resource governance
- Policy-as-code
- Defense in depth
- Credential isolation
