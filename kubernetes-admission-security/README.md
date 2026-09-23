# Kubernetes Admission Security

## What This Does

This implementation demonstrates Kubernetes admission security using the built-in Pod Security Admission mechanism and Pod Security Standards.

It validates namespace-level security boundaries using:

- Privileged
- Baseline
- Restricted

The workflow deliberately submits compliant and non-compliant Pods and Deployments to prove which workloads are admitted and which are prevented from creating Pods.

It also demonstrates mixed enforcement where Baseline is enforced while Restricted violations generate warnings and audit annotations.

## Architecture

```text
                    kubectl / API Request
                            |
                            v
                 +----------------------+
                 |    kube-apiserver    |
                 +----------+-----------+
                            |
                            v
                 +----------------------+
                 | Admission Controllers|
                 +----------+-----------+
                            |
                            v
                 +----------------------+
                 | PodSecurity Admission|
                 +----------+-----------+
                            |
          +-----------------+-----------------+
          |                 |                 |
          v                 v                 v
 +----------------+ +----------------+ +----------------+
 |   Privileged   | |    Baseline    | |   Restricted   |
 |   Namespace    | |   Namespace    | |   Namespace    |
 +----------------+ +----------------+ +----------------+
          |                 |                 |
          +-----------------+-----------------+
                            |
                            v
                 Allow / Warn / Reject
                            |
                            v
                  Kubernetes Workloads
```

## Prerequisites

- Ubuntu 24.04 LTS or compatible Linux environment
- sudo access
- containerd
- Kubernetes installed with kubeadm
- kubelet
- kubectl
- jq
- curl
- working container networking
- access to container registries

Validated environment:

```text
Ubuntu 24.04.3 LTS
Kubernetes 1.36.x
containerd runtime
Flannel CNI
single-node kubeadm control plane
```

## Setup & Installation

A single-node Kubernetes control plane was initialized with kubeadm.

Example:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<CONTROL_PLANE_IP> \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock
```

Flannel was installed as the CNI.

The control-plane scheduling taint was removed so test workloads could run on the single available node.

## How to Reproduce

### Inspect Admission Controller Configuration

Identify the kube-apiserver:

```bash
kubectl get pods \
  -n kube-system \
  -l component=kube-apiserver
```

Inspect admission-related command flags:

```bash
kubectl get pod <API_SERVER_POD> \
  -n kube-system \
  -o json \
  | jq -r '
      .spec.containers[0].command[]
      | select(
          startswith("--enable-admission-plugins=")
          or startswith("--disable-admission-plugins=")
          or startswith("--admission-control-config-file=")
        )
    '
```

A kubeadm control plane may use the built-in default admission configuration without explicitly listing PodSecurity in an enable flag.

The implementation therefore performs behavioral verification instead of relying only on command-line flags.

### Verify Pod Security Admission Behavior

Create a Restricted verification namespace:

```bash
kubectl create namespace psa-verification

kubectl label namespace psa-verification \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

Submit an intentionally privileged Pod using server-side dry-run.

Expected result:

```text
REJECTED
```

Submit a Restricted-compliant Pod through the same admission path.

Expected result:

```text
ADMITTED
```

This confirms that Pod Security Admission is enforcing security policy.

### Namespace Security Profiles

Three namespaces represent different trust levels:

```text
restricted-test
baseline-test
privileged-test
```

Each namespace uses explicit policy labels for:

```text
enforce
enforce-version
audit
audit-version
warn
warn-version
```

Example Restricted configuration:

```bash
kubectl label namespace restricted-test \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=<KUBERNETES_MINOR> \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=<KUBERNETES_MINOR> \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=<KUBERNETES_MINOR>
```

Explicit policy versions provide predictable behavior across Kubernetes upgrades.

## Privileged Workload

The privileged workload intentionally uses high-risk settings:

```yaml
securityContext:
  privileged: true
  runAsUser: 0
  capabilities:
    add:
      - SYS_ADMIN
      - NET_ADMIN
```

It also mounts a hostPath volume.

Expected admission behavior:

```text
restricted-test -> REJECTED
baseline-test   -> REJECTED
privileged-test -> ADMITTED
```

## Baseline Workload

The Baseline workload avoids privileged behavior but intentionally does not implement every Restricted requirement.

Expected behavior:

```text
restricted-test -> REJECTED
baseline-test   -> ADMITTED
privileged-test -> ADMITTED
```

## Restricted Workload

The hardened workload uses:

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
```

Container-level controls include:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
```

Expected behavior:

```text
restricted-test -> ADMITTED
baseline-test   -> ADMITTED
privileged-test -> ADMITTED
```

## Pod Security Admission Matrix

```text
+----------------------+------------+----------+------------+
| Workload             | Restricted | Baseline | Privileged |
+----------------------+------------+----------+------------+
| Privileged Pod       | Reject     | Reject   | Allow      |
| Baseline Pod         | Reject     | Allow    | Allow      |
| Restricted Pod       | Allow      | Allow    | Allow      |
+----------------------+------------+----------+------------+
```

## Deployment Enforcement

Higher-level Kubernetes controllers introduce an important security behavior.

A Deployment resource can exist even when its Pod template violates namespace security policy.

The flow is:

```text
Deployment
    |
    v
ReplicaSet
    |
    v
Attempts Pod creation
    |
    v
Pod Security Admission
    |
    +--> compliant      -> Pod created
    |
    +--> non-compliant  -> FailedCreate
```

For example:

```text
Privileged Deployment in Restricted namespace

Deployment: created
ReplicaSet: created
Pods:       blocked
```

ReplicaSet events provide the actual enforcement evidence.

This distinction is important when troubleshooting a Deployment that exists but has zero available replicas.

## Deployment Security Matrix

```text
Privileged Deployment
  Restricted -> Pod creation blocked
  Baseline   -> Pod creation blocked
  Privileged -> Pods admitted

Baseline Deployment
  Restricted -> Pod creation blocked
  Baseline   -> Pods admitted

Restricted Deployment
  Restricted -> Pods admitted
  Baseline   -> Pods admitted
  Privileged -> Pods admitted
```

## Mixed Enforcement

An additional namespace demonstrates separate policies for enforcement, warning, and auditing:

```text
mixed-policy-test

enforce = baseline
audit   = restricted
warn    = restricted
```

The admission modes provide different behavior:

```text
enforce
  Blocks requests that violate the configured policy.

warn
  Allows the request but returns policy warnings to the client.

audit
  Adds policy violation information to audit annotations when API
  audit logging is configured.
```

This enables gradual policy adoption.

Example migration:

```text
Phase 1

enforce=baseline
warn=restricted
audit=restricted

        |
        v

Remediate workloads

        |
        v

Phase 2

enforce=restricted
warn=restricted
audit=restricted
```

## Custom Security Context

A custom workload demonstrates explicit Linux identity and container-security controls.

Pod-level configuration:

```yaml
securityContext:
  runAsUser: 2000
  runAsGroup: 2000
  fsGroup: 2000
  supplementalGroups:
    - 3000
    - 4000
  seccompProfile:
    type: RuntimeDefault
```

Container-level configuration:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE
```

Runtime validation:

```bash
kubectl exec \
  -n <NAMESPACE> \
  custom-security-pod \
  -- id
```

This confirms the workload uses the intended non-root Linux identity.

## Policy Violation Analysis

Policy failures are investigated through Kubernetes events:

```bash
kubectl get events \
  -n restricted-test \
  --sort-by='.lastTimestamp'
```

For controller-managed workloads, ReplicaSet events can expose errors such as:

```text
FailedCreate
violates PodSecurity
```

API server logs can also be inspected for admission-related activity.

## Security Controls Demonstrated

- privileged container prevention
- hostPath restriction
- Linux capability restrictions
- non-root execution
- privilege escalation prevention
- RuntimeDefault seccomp
- read-only root filesystems
- namespace-level security boundaries
- explicit security-policy version pinning
- server-side admission testing
- warning-mode evaluation
- audit-mode configuration
- controller-level Pod admission behavior
- security policy migration patterns

## Tools Used

- Kubernetes
- kubeadm
- kubelet
- kubectl
- containerd
- Flannel
- Pod Security Admission
- Pod Security Standards
- Bash
- jq
- curl

## Key Skills Demonstrated

- Kubernetes admission control
- Pod Security Admission
- Pod Security Standards
- namespace security architecture
- privileged workload restriction
- Linux container security contexts
- capability management
- seccomp configuration
- non-root enforcement
- server-side dry-run validation
- Deployment and ReplicaSet troubleshooting
- Kubernetes event analysis
- security-policy enforcement testing
- defense-in-depth for container platforms

## Real-World Use Case

Different Kubernetes workloads may require different privilege levels.

Example:

```text
Platform infrastructure
        |
        v
Privileged policy

General application workloads
        |
        v
Baseline policy

Sensitive production workloads
        |
        v
Restricted policy
```

Without admission controls, a user with Pod creation rights could potentially request:

- privileged containers
- dangerous Linux capabilities
- host filesystem access
- root execution
- privilege escalation

Pod Security Admission provides a native Kubernetes control for preventing unsafe Pod configurations before they run.

A staged deployment strategy can begin with:

```text
enforce=baseline
warn=restricted
audit=restricted
```

and later transition to:

```text
enforce=restricted
```

after workloads have been hardened.

## Lessons Learned

- Admission controllers evaluate Kubernetes API requests before workloads are accepted.
- Pod Security Admission is controlled through namespace labels.
- Privileged, Baseline, and Restricted provide progressively stronger security boundaries.
- Explicit version labels improve policy predictability.
- Behavioral admission testing is stronger evidence than API discovery alone.
- Server-side dry-run can validate security policies without creating runtime resources.
- Privileged containers are blocked by Baseline and Restricted policies.
- Baseline-compliant workloads can still violate Restricted policy.
- Restricted workloads require stronger security contexts.
- `allowPrivilegeEscalation: false` is an important hardening control.
- Restricted workloads should drop Linux capabilities unless specifically required.
- RuntimeDefault seccomp provides syscall filtering.
- `runAsNonRoot` prevents intentional root execution.
- Deployment admission and Pod admission are separate events.
- A Deployment can exist while its Pods are blocked.
- ReplicaSet events are essential for diagnosing policy failures.
- Warn mode evaluates policy without blocking workloads.
- Audit mode requires API audit logging to persist audit records.
- Mixed enforcement supports incremental policy adoption.
- Security testing should include both expected failures and expected successes.

## Troubleshooting Log

### Fresh Environment Had No Kubernetes Cluster

The starting machine contained Docker, containerd, and kubectl but no kubeadm control plane.

A fresh kubeadm Kubernetes control plane was initialized and configured with Flannel before admission-security validation began.

### API Discovery Was Not Sufficient

Listing admission-related API versions does not prove that Pod Security Admission is enforcing policy.

The admission path was therefore validated directly using server-side dry-run requests.

A privileged Pod was rejected by a Restricted namespace while a compliant Pod was admitted.

### No Explicit PodSecurity Enable Flag

The kube-apiserver used the built-in default admission plugin configuration.

The implementation verified that PodSecurity was not explicitly disabled and then confirmed enforcement behavior directly.

### Policy Versions Were Pinned

Namespace policy labels used the active Kubernetes minor version instead of implicitly depending on `latest`.

This improves reproducibility across Kubernetes upgrades.

### Deployment Creation Did Not Guarantee Pod Creation

A non-compliant Deployment can exist while its ReplicaSet fails to create Pods.

The enforcement evidence therefore appears in ReplicaSet events.

### Restricted Workloads Required Explicit Hardening

Restricted-compatible workloads implemented:

```text
runAsNonRoot
RuntimeDefault seccomp
allowPrivilegeEscalation=false
capabilities.drop=ALL
```

Missing required controls caused Pod admission to fail.

### Mixed Enforcement Produced Different Outcomes

A namespace configured with:

```text
enforce=baseline
audit=restricted
warn=restricted
```

could admit Baseline workloads while evaluating them against Restricted policy.

This demonstrates gradual security-policy adoption.

### Audit Persistence Depends on API Audit Configuration

Pod Security Admission can generate audit annotations.

Persistent audit records require Kubernetes API audit logging to be configured.

### Cleanup Preserved Security Evidence

Runtime namespaces, Pods, and Deployments were removed after validation.

Reusable manifests, policy matrices, admission results, event evidence, and security-context records were retained for reproducibility and review.
