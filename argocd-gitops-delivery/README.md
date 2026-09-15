# Argo CD GitOps Delivery

A Kubernetes GitOps implementation using Argo CD to manage application delivery, continuous reconciliation, configuration updates, drift correction, automated pruning, and failure recovery from Git.

The implementation treats Git as the source of truth and validates the full reconciliation lifecycle from repository commit to live Kubernetes state.

## Architecture

~~text
Developer
   |
   | git commit / push
   v
GitHub Repository
   |
   | desired Kubernetes state
   v
Argo CD Repo Server
   |
   v
Argo CD Application Controller
   |
   | reconciliation
   v
Kubernetes API
   |
   v
sample-app
   |
   +-- Deployment
   +-- Service
   +-- ConfigMap
~~

## Core Capabilities

- declarative Kubernetes delivery from Git
- Argo CD Application resources
- automated synchronization
- Git-based image and replica updates
- continuous reconciliation
- self-healing from live-cluster drift
- automated resource pruning
- ConfigMap-driven application content
- deployment health probes
- sync revision tracking
- controlled deployment failure testing
- Kubernetes event-based troubleshooting
- Git-based application recovery
- Argo CD sync history inspection

## Technology Stack

| Component | Purpose |
|---|---|
| Kubernetes | Application runtime |
| Argo CD | GitOps reconciliation engine |
| GitHub | Desired-state source |
| Minikube | Kubernetes environment |
| kubectl | Kubernetes administration |
| argocd CLI | GitOps inspection and diagnostics |
| Git | Versioned configuration management |
| NGINX | Sample application workload |

## Repository Structure

~~text
argocd-gitops-delivery/
├── README.md
├── apps/
│   └── sample-app/
│       ├── namespace.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
└── argocd/
    └── sample-app.yaml
~~

## GitOps Model

The application is not deployed by manually applying workload manifests.

Instead:

~~text
Git commit
   |
   v
GitHub main branch
   |
   v
Argo CD detects revision
   |
   v
Argo CD compares desired and live state
   |
   v
Kubernetes resources reconciled
~~

This keeps deployment state versioned and auditable.

## Argo CD Application

The Argo CD Application points to the application manifests stored in this repository.

~~yaml
source:
  repoURL: https://github.com/bilalfayyaz11/kubernetes-cloud-native-engineering.git
  targetRevision: main
  path: argocd-gitops-delivery/apps/sample-app
~~

The destination is the local Kubernetes cluster:

~~yaml
destination:
  server: https://kubernetes.default.svc
  namespace: sample-app
~~

## Automated Synchronization

The application uses automated synchronization:

~~yaml
syncPolicy:
  automated:
    enabled: true
    prune: true
    selfHeal: true
~~

This enables three important behaviors:

~~text
automatic sync  -> apply new desired state from Git
self-heal       -> restore unauthorized live-cluster changes
prune           -> remove resources deleted from Git
~~

## Git-Driven Deployment Update

The application was updated through Git by changing:

~~text
replicas: 2 -> 3
image: nginx:1.29-alpine -> nginx:1.29.1-alpine
~~

The workflow was:

~~text
edit manifest
   ↓
git commit
   ↓
git push
   ↓
Argo CD detects new revision
   ↓
automatic synchronization
   ↓
Kubernetes rollout
~~

No manual workload `kubectl apply` was required.

## Drift Detection and Self-Healing

Live state was intentionally modified directly:

~~text
replicas -> 1
image    -> nginx:1.28-alpine
~~

Git remained unchanged.

Because self-healing was enabled, Argo CD reconciled the Deployment back to the repository-defined state:

~~text
replicas -> 3
image    -> nginx:1.29.1-alpine
~~

This demonstrates that the Kubernetes cluster is not treated as the source of truth.

## ConfigMap-Driven Application Configuration

Application content is managed through:

~~text
apps/sample-app/configmap.yaml
~~

The ConfigMap provides:

~~text
index.html
app.properties
~~

The deployment mounts the HTML file into NGINX:

~~yaml
volumeMounts:
- name: config-volume
  mountPath: /usr/share/nginx/html/index.html
  subPath: index.html
~~

This allows application configuration and content to participate in the same GitOps delivery workflow.

## Automated Pruning

A temporary ConfigMap was:

~~text
1. created in Git
2. committed and pushed
3. synchronized into Kubernetes
4. removed from Git
5. automatically deleted from Kubernetes by Argo CD
~~

This validates:

~~yaml
prune: true
~~

and proves that Git controls both creation and removal of managed resources.

## Health Checks

The workload includes Kubernetes readiness and liveness probes.

~~yaml
readinessProbe:
  httpGet:
    path: /
    port: http

livenessProbe:
  httpGet:
    path: /
    port: http
~~

These checks allow Kubernetes and Argo CD to report meaningful health state during rollouts and failures.

## Failure Simulation

A controlled deployment failure was introduced through Git by changing the image to:

~~text
nonexistent-image-for-gitops-validation:latest
~~

Argo CD synchronized the desired state, causing Kubernetes to surface image pull failures such as:

~~text
ErrImagePull
ImagePullBackOff
~~

The failure was investigated using:

~~bash
argocd app get sample-app --core

kubectl get pods -n sample-app

kubectl describe deployment sample-app -n sample-app

kubectl describe pod <pod> -n sample-app

kubectl get events -n sample-app --sort-by='.lastTimestamp'
~~

This demonstrates troubleshooting at both the GitOps control-plane and Kubernetes workload layers.

## Git-Based Recovery

The broken image was repaired by restoring the known-good image in Git.

~~text
broken Git revision
       ↓
failure observed
       ↓
manifest corrected
       ↓
recovery commit
       ↓
git push
       ↓
Argo CD reconciliation
       ↓
healthy Kubernetes rollout
~~

The live cluster was not repaired manually.

## Sync and Revision Inspection

Argo CD application state can be inspected with:

~~bash
kubectl get application sample-app \
  -n argocd \
  -o jsonpath='Sync={.status.sync.status}{"\n"}Health={.status.health.status}{"\n"}Revision={.status.sync.revision}{"\n"}'
~~

Sync history:

~~bash
argocd app history sample-app --core
~~

Detailed state:

~~bash
argocd app get sample-app --core
~~

## Validation Summary

~~text
Argo CD control plane        VERIFIED
GitHub repository source     VERIFIED
Application sync             VERIFIED
Git-only updates             VERIFIED
Replica reconciliation       VERIFIED
Image reconciliation         VERIFIED
Self-healing                 VERIFIED
Live-cluster drift repair    VERIFIED
ConfigMap delivery           VERIFIED
Custom application content   VERIFIED
Automated pruning            VERIFIED
Failure detection            VERIFIED
Event-based troubleshooting  VERIFIED
Git-based recovery           VERIFIED
Health probes                VERIFIED
Sync history                 VERIFIED
~~

## Security and Operational Notes

The repository is public, so Argo CD can read the manifests without storing Git credentials in the cluster.

For private production repositories, repository authentication should be handled through secure Argo CD repository credentials or an external secret management mechanism.

Production deployments should also consider:

- protected Git branches
- pull-request approvals
- signed commits
- environment-specific repositories or overlays
- RBAC within Argo CD
- SSO integration
- encrypted secrets
- notification integrations
- high-availability Argo CD
- production monitoring
- disaster recovery
- policy enforcement before synchronization

## Engineering Takeaways

This implementation demonstrates the practical difference between traditional imperative deployment and GitOps.

Traditional workflow:

~~text
operator -> kubectl apply -> cluster
~~

GitOps workflow:

~~text
operator -> Git -> Argo CD -> cluster
~~

The GitOps model provides:

- declarative desired state
- deployment traceability
- repeatable reconciliation
- drift correction
- safer recovery
- auditable infrastructure changes
- consistent application delivery

These patterns are directly applicable to DevOps, platform engineering, SRE, Kubernetes operations, and cloud-native application delivery.
