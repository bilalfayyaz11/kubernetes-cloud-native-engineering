# Kubernetes Workload Hardening with SecurityContext and Pod Security Standards

## What This Does

This implementation demonstrates how to harden Kubernetes workloads using SecurityContext controls, Linux capability minimization, read-only root filesystems, seccomp, non-root execution, and Pod Security Admission.

The environment compares an unrestricted baseline pod against progressively hardened workloads, validates the runtime effect of each control, and demonstrates how application functionality can be preserved through narrowly scoped writable volumes.

It also tests the practical impact of Linux capabilities such as `NET_ADMIN`, enforces the Restricted Pod Security Standard in a dedicated namespace, intentionally introduces broken security configurations for troubleshooting, and provides reusable scripts for validating live container security state.

## Architecture

    Kubernetes Cluster
            |
            +---------------------------------------------------+
            |                                                   |
            v                                                   v
    Default Namespace                                  Restricted Namespace
            |                                                   |
    +-------+---------+                               +---------+----------+
    |                 |                               |                    |
    v                 v                               v                    v
 basic-pod       restricted-pod               pss-restricted-pod    PSA Enforcement
    |                 |                               |                    |
    |                 |                               |                    |
 root/default     non-root                            non-root          Restricted
 writable root    read-only root                      read-only root    admission policy
 capabilities     drop ALL                            drop ALL
                  seccomp                             seccomp
                  no escalation                       no escalation
            |
            +---------------------------+
            |                           |
            v                           v
      secure-webapp               Capability Tests
            |                     +-------------+
            |                     |             |
            v                     v             v
        Nginx 8080          netadmin-pod   no-netadmin-pod
            |                  NET_ADMIN       drop ALL
            v
    ClusterIP Service

Validation Layer
        |
        +--> security-analysis.sh
        +--> security-validation.sh
        +--> runtime /proc/1/status inspection
        +--> security-evidence.txt

## Prerequisites

- Linux environment
- Kubernetes cluster
- kubectl
- Valid kubeconfig context
- Permission to create Pods, ConfigMaps, Services, and Namespaces
- Container runtime with seccomp support
- Internet access for pulling container images
- AppArmor or another host LSM where available

Validate the cluster:

    kubectl cluster-info
    kubectl get nodes
    kubectl config current-context

Validate permissions:

    kubectl auth can-i create pods
    kubectl auth can-i create configmaps
    kubectl auth can-i create namespaces

For a lightweight single-node environment, K3s can be used:

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

No host-level application dependencies are required beyond Kubernetes tooling.

Apply the baseline workload:

    kubectl apply -f basic-pod.yaml

Apply the restricted workload:

    kubectl apply -f restricted-pod.yaml

Apply the secure Nginx workload:

    kubectl apply -f secure-webapp.yaml

Apply the secure service:

    kubectl apply -f secure-webapp-service.yaml

Apply the capability test workloads:

    kubectl apply -f netadmin-pod.yaml
    kubectl apply -f no-netadmin-pod.yaml

Apply the Restricted Pod Security Standard workload:

    kubectl apply -f pss-restricted-pod.yaml

## How to Reproduce

### 1. Establish an Unrestricted Baseline

Deploy:

    kubectl apply -f basic-pod.yaml

Inspect identity:

    kubectl exec basic-pod -- id

Inspect capabilities:

    kubectl exec basic-pod -- \
      sh -c 'grep -E "^Cap(Inh|Prm|Eff|Bnd|Amb):" /proc/1/status'

Inspect privilege and seccomp state:

    kubectl exec basic-pod -- \
      sh -c 'grep -E "^(NoNewPrivs|Seccomp):" /proc/1/status'

Test root filesystem writes:

    kubectl exec basic-pod -- \
      touch /baseline-root-write

The baseline demonstrates the security posture of a workload without explicit hardening.

### 2. Apply a Restricted SecurityContext

Deploy:

    kubectl apply -f restricted-pod.yaml

The workload uses:

    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000

    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true

    capabilities:
      drop:
        - ALL

    seccompProfile:
      type: RuntimeDefault

Verify identity:

    kubectl exec restricted-pod -- id

Verify capabilities:

    kubectl exec restricted-pod -- \
      grep CapEff /proc/1/status

Expected:

    CapEff: 0000000000000000

Verify read-only root filesystem:

    kubectl exec restricted-pod -- \
      touch /test-root-write

This should fail.

### 3. Provide Only Required Writable Paths

The hardened workload mounts temporary writable volumes at:

    /tmp
    /var/cache/nginx
    /var/run

Verify:

    kubectl exec restricted-pod -- \
      touch /tmp/test-write

This pattern preserves a read-only root filesystem while still allowing application runtime writes where required.

### 4. Run a Real Application Under Hardening

Deploy:

    kubectl apply -f secure-webapp.yaml

The Nginx workload runs on:

    8080

with:

    non-root UID
    read-only root filesystem
    dropped capabilities
    RuntimeDefault seccomp
    privilege escalation disabled

Verify the application:

    kubectl exec secure-webapp -- \
      wget -qO- http://127.0.0.1:8080

Expected output:

    Hello from Secure Web App!

### 5. Validate Service Connectivity

Apply:

    kubectl apply -f secure-webapp-service.yaml

Inspect:

    kubectl get service secure-webapp-service

Verify service backends:

    kubectl get endpointslice \
      -l kubernetes.io/service-name=secure-webapp-service

A temporary client can be used to test HTTP connectivity through the Service.

### 6. Compare Linux Capabilities

The no-capability workload uses:

    capabilities:
      drop:
        - ALL

The capability test workload drops everything except:

    NET_ADMIN

Verify runtime capability state:

    kubectl exec netadmin-pod -- \
      grep CapEff /proc/1/status

Test network administration:

    kubectl exec netadmin-pod -- \
      ip link add dummy0 type dummy

Verify:

    kubectl exec netadmin-pod -- \
      ip addr show dummy0

Remove:

    kubectl exec netadmin-pod -- \
      ip link delete dummy0

### 7. Compare Against a Pod Without NET_ADMIN

Run:

    kubectl exec no-netadmin-pod -- \
      ip link add dummy0 type dummy

Expected:

    Operation not permitted

This demonstrates why Linux capabilities should be dropped by default and selectively added only when genuinely required.

## Runtime Verification

SecurityContext declarations should not be trusted blindly.

Inspect the live process:

    grep CapEff /proc/1/status
    grep NoNewPrivs /proc/1/status
    grep Seccomp /proc/1/status

Important runtime indicators include:

    CapEff
    CapBnd
    NoNewPrivs
    Seccomp

Runtime verification confirms whether security controls are actually effective inside the container.

## Pod Security Standards

Create a dedicated namespace:

    kubectl create namespace restricted-security

Enforce Restricted Pod Security Admission:

    kubectl label namespace restricted-security \
      pod-security.kubernetes.io/enforce=restricted \
      pod-security.kubernetes.io/enforce-version=latest \
      pod-security.kubernetes.io/audit=restricted \
      pod-security.kubernetes.io/audit-version=latest \
      pod-security.kubernetes.io/warn=restricted \
      pod-security.kubernetes.io/warn-version=latest

Deploy the compliant workload:

    kubectl apply -f pss-restricted-pod.yaml

Verify:

    kubectl get pod \
      -n restricted-security \
      pss-restricted-pod

A privileged or otherwise noncompliant workload submitted to this namespace should be rejected by admission control.

## Security Analysis

Run:

    ./security-analysis.sh

The script compares:

    basic-pod
    restricted-pod
    secure-webapp
    netadmin-pod
    no-netadmin-pod

It records:

    UID
    GID
    root filesystem writability
    CapEff
    NoNewPrivs
    Seccomp mode

This provides a quick runtime comparison between unrestricted and hardened workloads.

## Security Validation

Run:

    ./security-validation.sh restricted-pod

Or specify another namespace:

    ./security-validation.sh \
      pss-restricted-pod \
      restricted-security

The validator checks:

    non-root execution
    read-only root filesystem
    effective capabilities
    privilege escalation
    seccomp
    declared SecurityContext

## Troubleshooting

### Conflicting runAsNonRoot and UID 0

A workload using:

    runAsNonRoot: true
    runAsUser: 0

contains contradictory requirements.

The runtime correctly prevents normal execution.

Fix:

    runAsNonRoot: true
    runAsUser: 1000

### Read-Only Root Filesystem Breaks Applications

Applications often need writable paths even when the root filesystem is locked.

Typical examples:

    /tmp
    /var/cache/nginx
    /var/run

Fix:

Mount narrowly scoped writable volumes instead of disabling the read-only root filesystem.

### Capability Declared but Not Effective

A capability can be declared in YAML without appearing in the live process capability set.

Always verify:

    grep CapEff /proc/1/status

and test the operation itself.

During testing, the initial non-root `NET_ADMIN` workload showed:

    CapEff: 0000000000000000

and network modification failed.

The capability experiment was corrected by isolating a controlled root container that dropped all capabilities except `NET_ADMIN`.

This demonstrated the capability itself without using privileged mode.

### Pod Security Admission Rejection

A Restricted namespace rejects workloads that violate the configured Pod Security Standard.

The admission error should be treated as a security signal rather than bypassed.

Correct the workload SecurityContext instead of weakening namespace policy.

## Tools Used

- Kubernetes
- K3s
- kubectl
- SecurityContext
- Pod Security Admission
- Pod Security Standards
- Linux capabilities
- seccomp
- AppArmor
- Nginx
- BusyBox
- netshoot
- curl
- EndpointSlice
- ConfigMap
- emptyDir
- Bash
- Linux `/proc`

## Key Skills Demonstrated

- Hardening Kubernetes workloads with SecurityContext
- Enforcing non-root container execution
- Implementing read-only container root filesystems
- Designing narrowly scoped writable mounts
- Disabling privilege escalation
- Dropping Linux capabilities by default
- Testing and validating Linux capabilities
- Inspecting live runtime capability state
- Applying RuntimeDefault seccomp profiles
- Enforcing Restricted Pod Security Standards
- Using Pod Security Admission namespace policies
- Troubleshooting conflicting SecurityContext settings
- Maintaining application functionality under restrictive controls
- Building reusable security validation tooling
- Capturing runtime security evidence
- Comparing declared configuration against effective runtime behavior

## Real-World Use Case

These controls are applicable to production Kubernetes environments where application teams require strong workload isolation without sacrificing functionality. Platform and security teams can standardize non-root execution, read-only root filesystems, seccomp, capability minimization, and Pod Security Standards across application namespaces. The same controls help reduce the blast radius of compromised containers, support compliance requirements, and prevent common privilege-escalation paths.

## Lessons Learned

- Kubernetes workloads should be tested under least-privilege conditions rather than hardened only after deployment.
- A read-only root filesystem is practical when writable runtime paths are explicitly mounted.
- Linux capabilities should be treated as powerful privileges, not convenience flags.
- `NET_ADMIN` materially changes what a process can do inside its network namespace.
- Runtime evidence is more reliable than assuming the YAML was enforced exactly as intended.
- Pod Security Admission adds cluster-side enforcement instead of relying only on developer discipline.
- SecurityContext errors often reveal real incompatibilities between application behavior and hardened runtime requirements.
- Strong security controls can coexist with normal application functionality when application write paths and ports are designed correctly.

## Security Evidence

The following files capture the final runtime validation results:

    security-evidence.txt
    final-security-analysis.txt
    restricted-pod-validation.txt
    pss-restricted-validation.txt

These provide evidence of:

    UID/GID configuration
    effective capabilities
    seccomp state
    privilege-escalation prevention
    root filesystem behavior
    Restricted Pod Security Standard enforcement

## Production Hardening

A production Kubernetes environment should also consider:

- Admission policy through Pod Security Admission or policy engines
- Image signature verification
- Image vulnerability scanning
- NetworkPolicies
- Runtime threat detection
- AppArmor or SELinux profiles
- Resource requests and limits
- ServiceAccount isolation
- Restricted RBAC
- Secrets management
- Immutable container images
- Automated policy testing
- GitOps enforcement
- SecurityContext defaults in workload templates
- Continuous compliance validation
