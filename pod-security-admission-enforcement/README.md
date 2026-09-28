# Kubernetes Pod Security Admission Enforcement

## Overview

This implementation demonstrates Kubernetes Pod Security Admission at the namespace level using both Baseline and Restricted Pod Security Standards.

The environment proves how Kubernetes admission control can prevent insecure workload configurations before they reach a node while still allowing correctly hardened applications to operate successfully.

Two security zones are implemented:

- `baseline-test`
- `restricted-test`

The workflow intentionally submits both compliant and non-compliant workloads to compare admission behavior between the two policy levels.

## Architecture

```text
                     Kubernetes API Server
                              |
                              v
                   Pod Security Admission
                              |
              +---------------+---------------+
              |                               |
              v                               v
      baseline-test                    restricted-test
      enforce: baseline                enforce: restricted
              |                               |
      +-------+--------+              +-------+--------+
      |                |              |                |
      v                v              v                v
 compliant         privileged     hardened         incomplete
 workload          / host-level   workload         workload
      |             workload          |                |
      v                |              v                |
   ALLOWED             v           ALLOWED             v
                    DENIED                           DENIED
```

## Security Policy Model

### Baseline

Baseline provides a minimum workload security boundary while maintaining compatibility with common Kubernetes applications.

The following unsafe configurations were tested:

- Privileged containers
- `hostNetwork`
- `hostPID`
- `hostIPC`
- `hostPath` volumes

These configurations were rejected by admission control in the Baseline namespace.

### Restricted

Restricted applies stronger workload-hardening requirements.

Restricted workloads were configured with:

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
```

Container-level controls included:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
```

The final application additionally used:

- Read-only root filesystem
- Explicit writable `emptyDir` volumes
- CPU requests and limits
- Memory requests and limits
- Liveness probes
- Readiness probes

## Environment

The implementation was validated using:

```text
Ubuntu 24.04 LTS
Kubernetes / K3s
kubectl
containerd
Pod Security Admission
```

The fresh machine initially contained `kubectl` but no active Kubernetes cluster, kubeconfig, API server, or usable Kubernetes context.

A fresh K3s cluster was therefore bootstrapped before Pod Security Admission testing.

## Namespace Policies

### Baseline Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: baseline-test
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: v1.36
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/audit-version: v1.36
    pod-security.kubernetes.io/warn: baseline
    pod-security.kubernetes.io/warn-version: v1.36
```

### Restricted Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: restricted-test
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.36
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.36
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.36
```

Policy versions were explicitly pinned to make admission behavior predictable and reproducible.

## Apply Namespace Policies

```bash
export KUBECONFIG="$HOME/.kube/config"

kubectl apply -f baseline-namespace.yaml
kubectl apply -f restricted-namespace.yaml
```

Verify labels:

```bash
kubectl get namespace baseline-test restricted-test \
  -L pod-security.kubernetes.io/enforce \
  -L pod-security.kubernetes.io/enforce-version
```

## Baseline Enforcement

A compliant non-root workload was first deployed successfully.

```bash
kubectl apply -f compliant-pod.yaml

kubectl wait \
  --for=condition=Ready \
  pod/compliant-app \
  -n baseline-test \
  --timeout=120s
```

The following deliberately unsafe workloads were then evaluated through server-side admission.

### Privileged Container

```bash
kubectl apply \
  --dry-run=server \
  -f privileged-pod.yaml
```

Expected result:

```text
DENIED
```

### Host Network

```bash
kubectl apply \
  --dry-run=server \
  -f host-network-pod.yaml
```

Expected result:

```text
DENIED
```

### Host Path

```bash
kubectl apply \
  --dry-run=server \
  -f hostpath-pod.yaml
```

Expected result:

```text
DENIED
```

### Host PID

```bash
kubectl apply \
  --dry-run=server \
  -f hostpid-pod.yaml
```

Expected result:

```text
DENIED
```

### Host IPC

```bash
kubectl apply \
  --dry-run=server \
  -f hostipc-pod.yaml
```

Expected result:

```text
DENIED
```

## Restricted Enforcement

A workload that was acceptable under the less restrictive Baseline configuration was evaluated against the Restricted namespace.

```bash
kubectl apply \
  --dry-run=server \
  -f compliant-pod-restricted.yaml
```

The workload was rejected because it did not satisfy the complete Restricted security profile.

### Fully Restricted-Compliant Pod

A hardened workload was then created with:

- Non-root execution
- Explicit non-root UID and GID
- `RuntimeDefault` seccomp
- Privilege escalation disabled
- All Linux capabilities dropped

Deploy:

```bash
kubectl apply -f fully-compliant-pod.yaml

kubectl wait \
  --for=condition=Ready \
  pod/fully-compliant-app \
  -n restricted-test \
  --timeout=120s
```

Verify:

```bash
kubectl get pod fully-compliant-app \
  -n restricted-test \
  -o wide
```

## Restricted Violation Tests

### Missing seccomp

```bash
kubectl apply \
  --dry-run=server \
  -f missing-seccomp-pod.yaml
```

Expected:

```text
DENIED
```

### Privilege Escalation Enabled

```bash
kubectl apply \
  --dry-run=server \
  -f privilege-escalation-pod.yaml
```

Expected:

```text
DENIED
```

### Disallowed Linux Capability

```bash
kubectl apply \
  --dry-run=server \
  -f capability-violation-pod.yaml
```

Expected:

```text
DENIED
```

## Baseline vs Restricted Comparison

The same Deployment definition was evaluated in both security zones.

Baseline:

```bash
kubectl apply \
  -n baseline-test \
  -f test-deployment.yaml
```

Result:

```text
ALLOWED
```

Restricted:

```bash
kubectl apply \
  --dry-run=server \
  -n restricted-test \
  -f test-deployment.yaml
```

Result:

```text
DENIED
```

This demonstrates that a workload accepted by Baseline may still require additional security controls before it can run under Restricted enforcement.

## Policy Comparison

```text
CONTROL                         BASELINE      RESTRICTED
------------------------------  ------------  ------------
Privileged container            denied        denied
hostNetwork                     denied        denied
hostPID                         denied        denied
hostIPC                         denied        denied
hostPath                        denied        denied
runAsNonRoot                    optional      required
allowPrivilegeEscalation=false  optional      required
RuntimeDefault seccomp          optional      required
Drop ALL capabilities           optional      required
```

## Restricted-Compliant Application

A reusable production-style application template was created for the Restricted namespace.

The Pod-level configuration included:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 101
  runAsGroup: 101
  fsGroup: 101
  seccompProfile:
    type: RuntimeDefault
```

The container-level configuration included:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 101
  runAsGroup: 101
  capabilities:
    drop:
      - ALL
```

A non-root NGINX image listening on port `8080` was used so the application could operate without privileged ports.

## Writable Runtime Paths

Because the container root filesystem is read-only, writable runtime paths were provided explicitly with `emptyDir` volumes:

```text
/tmp
/var/cache/nginx
/var/run
```

This keeps the root filesystem immutable while allowing the application to write only where necessary.

## Resource Governance

The secure Deployment defines explicit resource requests and limits:

```text
CPU request       50m
CPU limit         200m
Memory request    64Mi
Memory limit      128Mi
```

These resource controls complement workload security by limiting resource consumption.

## Health Checks

The final application includes:

- Readiness probe
- Liveness probe

These verify that the hardened workload remains healthy and operational under Restricted policy enforcement.

## Deploy Secure Application

```bash
kubectl apply -f secure-app-template.yaml

kubectl rollout status \
  deployment/secure-web-app \
  -n restricted-test \
  --timeout=180s
```

Verify:

```bash
kubectl get deployment secure-web-app \
  -n restricted-test

kubectl get pods \
  -n restricted-test \
  -l app=secure-web-app
```

## Service Connectivity

The application is exposed internally using a ClusterIP Service.

```bash
kubectl apply -f secure-app-service.yaml
```

Verify:

```bash
kubectl get service secure-web-service \
  -n restricted-test

kubectl get endpoints secure-web-service \
  -n restricted-test
```

A Restricted-compliant client Pod was used to test:

```text
http://secure-web-service
```

The request completed successfully, proving that security enforcement did not break application functionality.

## Admission Result Matrix

```text
CONFIGURATION                       BASELINE      RESTRICTED
----------------------------------  ------------  ------------
Compliant workload                  ALLOWED       depends on controls
Privileged container                DENIED        DENIED
hostNetwork                         DENIED        DENIED
hostPID                             DENIED        DENIED
hostIPC                             DENIED        DENIED
hostPath                            DENIED        DENIED
Missing seccomp                     ALLOWED       DENIED
Privilege escalation enabled        ALLOWED*      DENIED
Incomplete capability restrictions  ALLOWED*      DENIED
Fully hardened workload             ALLOWED       ALLOWED
Secure web application              ALLOWED       ALLOWED
```

`*` Subject to other Baseline restrictions in the submitted workload.

## Key Skills Demonstrated

- Kubernetes Pod Security Admission
- Pod Security Standards
- Baseline policy enforcement
- Restricted policy enforcement
- Namespace-level workload governance
- Server-side admission testing
- Security-context design
- Non-root container execution
- RuntimeDefault seccomp
- Linux capability reduction
- Privilege-escalation prevention
- Read-only root filesystems
- Explicit writable volume design
- Admission failure analysis
- Secure Deployment templates
- ClusterIP Services
- Readiness and liveness probes
- CPU and memory governance
- Positive and negative security testing

## Troubleshooting

### kubectl Installed but No Kubernetes Cluster

The fresh environment initially returned:

```text
No active Kubernetes context
Kubernetes cluster unavailable
```

Resolution:

- Bootstrapped K3s
- Configured the kubeconfig
- Waited for the Kubernetes API server
- Verified the node reached `Ready`
- Confirmed Pod Security Admission before workload testing

### Pod Rejected with `violates PodSecurity`

This indicates that Pod Security Admission rejected the workload before scheduling.

Use:

```bash
kubectl apply \
  --dry-run=server \
  -f workload.yaml
```

The admission response identifies which security controls are missing or prohibited.

### Baseline Workload Rejected by Restricted

This is expected.

Restricted requires stronger workload hardening than Baseline.

Typical required controls include:

```text
runAsNonRoot: true
allowPrivilegeEscalation: false
seccompProfile.type: RuntimeDefault
capabilities.drop:
  - ALL
```

### Application Passes Admission but Fails at Runtime

Admission compliance does not guarantee application compatibility.

Restricted workloads may also require:

- Non-root-compatible container images
- Unprivileged listening ports
- Writable volume mounts
- Correct file ownership
- Compatible startup commands
- Compatible health probes

The final application uses a non-root NGINX image with explicit writable runtime volumes.

### Read-Only Root Filesystem

Some applications need temporary writable paths even when the root filesystem is immutable.

The secure Deployment provides writable `emptyDir` mounts only for the paths that require them.

## Findings

The implementation demonstrated that Kubernetes can enforce workload security requirements directly at the API admission layer.

Baseline prevents common privilege escalation and direct host exposure while remaining compatible with many standard applications.

Restricted establishes a significantly stronger security posture by requiring workloads to explicitly adopt non-root execution, privilege-escalation prevention, seccomp, and capability restrictions.

The side-by-side comparison showed that workloads should not be assumed to be production-ready simply because they run successfully under Baseline.

Admission compliance must also be combined with runtime validation. The final secure application demonstrated that a workload can operate successfully with Restricted enforcement, a read-only root filesystem, explicit writable volumes, health probes, and resource boundaries.

## Real-World Application

Pod Security Admission can be used to establish different workload trust zones across Kubernetes clusters.

Example policy segmentation:

```text
Development namespaces        -> Baseline
General application workloads -> Baseline or Restricted
Sensitive systems             -> Restricted
Regulated environments        -> Restricted
Shared multi-team clusters    -> Namespace-specific enforcement
```

This allows platform and security teams to enforce organization-wide workload requirements without relying entirely on individual application teams to configure security manually.

## Final Results

```text
Baseline policy enforcement             PASS
Restricted policy enforcement           PASS
Privileged workload rejection           PASS
Host network rejection                  PASS
Host PID rejection                      PASS
Host IPC rejection                      PASS
HostPath rejection                      PASS
Restricted seccomp requirement          PASS
Privilege escalation prevention         PASS
Capability restriction                  PASS
Restricted-compliant Pod startup        PASS
Baseline vs Restricted comparison       PASS
Secure application deployment           PASS
Service connectivity                    PASS
Readiness probe                          PASS
Liveness probe                           PASS
Resource governance                     PASS
```

The final result is a practical implementation of Kubernetes admission-layer workload security using Pod Security Standards.
