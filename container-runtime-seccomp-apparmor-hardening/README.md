# Kubernetes Runtime Hardening with seccomp and AppArmor

## What This Does

This implementation applies defense-in-depth runtime controls to Kubernetes workloads using Linux seccomp and AppArmor. A custom seccomp profile restricts high-risk kernel system calls, while a Localhost AppArmor profile limits filesystem access, sensitive file reads, capabilities, and host-facing operations. The hardened workload also runs as a non-root user, drops all Linux capabilities, disables privilege escalation, uses a read-only root filesystem, and operates within explicit CPU and memory boundaries.

## Architecture

```text
                         Kubernetes Pod
                               |
                +--------------+--------------+
                |                             |
                v                             v
        Kubernetes Security            Linux Kernel Security
        Context Controls                     Controls
                |                             |
        +-------+--------+          +---------+----------+
        |                |          |                    |
        v                v          v                    v
   Non-root UID      Drop ALL    seccomp              AppArmor
                     caps        profile              profile
        |                |          |                    |
        |                |          |                    |
        +--------+-------+          |                    |
                 |                  |                    |
                 v                  v                    v
        No privilege        Block selected       Restrict files,
        escalation          syscalls              capabilities,
                 |          and kernel ops        process access
                 |                  |                    |
                 +------------------+--------------------+
                                    |
                                    v
                         Hardened Container
                                    |
            +-----------------------+-----------------------+
            |                       |                       |
            v                       v                       v
      Read-only root            Writable /tmp          Resources
      filesystem               via emptyDir         CPU + Memory
```

## Security Controls

```text
CONTROL                           ENFORCEMENT
--------------------------------  -----------------------------
Container user                    Non-root UID/GID 1000
Privilege escalation              Disabled
Linux capabilities                ALL dropped
Root filesystem                   Read-only
Temporary storage                 Writable /tmp emptyDir
seccomp                           Localhost profile
AppArmor                          Localhost profile
mount syscall                     Denied
Kernel module operations          Denied by seccomp
bpf syscall                       Denied by seccomp
/etc/shadow                       Denied by AppArmor
/sys modification                 Denied by AppArmor
Dangerous capabilities            Denied by AppArmor
CPU                               50m request / 100m limit
Memory                            64Mi request / 128Mi limit
```

## Prerequisites

- Ubuntu Linux with AppArmor enabled
- Kernel compiled with `CONFIG_SECCOMP=y`
- Kernel compiled with `CONFIG_SECCOMP_FILTER=y`
- Kubernetes cluster
- K3s or another Kubernetes distribution supporting Localhost security profiles
- kubectl
- containerd-compatible runtime
- AppArmor utilities
- apparmor_parser
- jq
- curl
- sudo access

## Setup & Installation

### Verify Host Security Support

```bash
grep -E '^CONFIG_SECCOMP|^CONFIG_SECCOMP_FILTER' \
  "/boot/config-$(uname -r)"

cat /sys/module/apparmor/parameters/enabled

sudo aa-status
```

Expected seccomp kernel configuration:

```text
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
```

Expected AppArmor state:

```text
Y
```

### Bootstrap Kubernetes

```bash
curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh

sudo sh /tmp/install-k3s.sh \
  --write-kubeconfig-mode=644 \
  --kubelet-arg=seccomp-default=true

mkdir -p "$HOME/.kube"

sudo cp \
  /etc/rancher/k3s/k3s.yaml \
  "$HOME/.kube/config"

sudo chown \
  "$(id -u):$(id -g)" \
  "$HOME/.kube/config"

chmod 600 "$HOME/.kube/config"

export KUBECONFIG="$HOME/.kube/config"

kubectl get nodes -o wide
```

Using `seccomp-default=true` establishes a safer runtime baseline for workloads that do not explicitly specify another seccomp profile.

## How to Reproduce

### 1. Install the Localhost seccomp Profile

For K3s, place Localhost seccomp profiles beneath the K3s kubelet seccomp root:

```bash
sudo mkdir -p \
  /var/lib/rancher/k3s/agent/kubelet/seccomp/profiles

sudo cp restricted-profile.json \
  /var/lib/rancher/k3s/agent/kubelet/seccomp/profiles/

sudo chmod 644 \
  /var/lib/rancher/k3s/agent/kubelet/seccomp/profiles/restricted-profile.json
```

Validate the JSON:

```bash
jq . restricted-profile.json
```

The profile keeps normal workload syscalls available while explicitly denying high-risk operations including:

```text
mount
umount2
pivot_root
kexec_load
kexec_file_load
init_module
finit_module
delete_module
reboot
swapon
swapoff
bpf
```

### 2. Deploy the seccomp-Hardened Workload

```bash
kubectl apply -f seccomp-pod.yaml

kubectl wait \
  --for=condition=Ready \
  pod/seccomp-test-pod \
  --timeout=120s
```

Confirm the configured profile:

```bash
kubectl get pod seccomp-test-pod \
  -o jsonpath='{.spec.securityContext.seccompProfile}'
```

### 3. Validate seccomp Enforcement

Normal operations should succeed:

```bash
kubectl exec seccomp-test-pod -- sh -c '
id
pwd
echo "allowed" > /tmp/allowed.txt
cat /tmp/allowed.txt
'
```

A restricted mount operation should fail:

```bash
kubectl exec seccomp-test-pod -- sh -c '
mkdir -p /tmp/seccomp-mount-test
mount -t tmpfs tmpfs /tmp/seccomp-mount-test
'
```

Expected result:

```text
Operation not permitted
```

### 4. Install the AppArmor Profile

```bash
sudo cp \
  containers.restricted-container \
  /etc/apparmor.d/containers.restricted-container

sudo apparmor_parser \
  -Q \
  /etc/apparmor.d/containers.restricted-container

sudo apparmor_parser \
  -r \
  /etc/apparmor.d/containers.restricted-container
```

Verify enforcement:

```bash
sudo aa-status \
  | grep containers.restricted-container
```

### 5. Deploy the AppArmor-Hardened Workload

```bash
kubectl apply -f apparmor-pod.yaml

kubectl wait \
  --for=condition=Ready \
  pod/apparmor-test-pod \
  --timeout=120s
```

The workload uses the modern Kubernetes AppArmor security context:

```yaml
securityContext:
  appArmorProfile:
    type: Localhost
    localhostProfile: containers.restricted-container
```

### 6. Validate AppArmor Enforcement

Approved `/tmp` access:

```bash
kubectl exec apparmor-test-pod -- sh -c '
echo "allowed" > /tmp/testfile
cat /tmp/testfile
'
```

Sensitive file access:

```bash
kubectl exec apparmor-test-pod -- \
  cat /etc/shadow
```

Expected result:

```text
Permission denied
```

Inspect kernel denial events:

```bash
sudo journalctl \
  -k \
  --no-pager \
  | grep -i 'apparmor="DENIED"'
```

### 7. Deploy the Defense-in-Depth Workload

```bash
kubectl apply -f hardened-pod.yaml

kubectl wait \
  --for=condition=Ready \
  pod/hardened-test-pod \
  --timeout=120s
```

The hardened workload combines:

```text
Localhost seccomp
Localhost AppArmor
runAsNonRoot
UID/GID 1000
allowPrivilegeEscalation=false
drop ALL capabilities
readOnlyRootFilesystem=true
writable /tmp emptyDir
CPU requests and limits
memory requests and limits
```

### 8. Verify Runtime Identity

```bash
kubectl exec hardened-test-pod -- id
```

Expected UID:

```text
1000
```

Inspect privilege and capability state:

```bash
kubectl exec hardened-test-pod -- sh -c '
grep -E "^NoNewPrivs:|^Cap(Inh|Prm|Eff|Bnd|Amb):" /proc/1/status
'
```

### 9. Validate Writable Temporary Storage

```bash
kubectl exec hardened-test-pod -- sh -c '
echo "approved-data" > /tmp/security-test.txt
cat /tmp/security-test.txt
'
```

This succeeds because `/tmp` is explicitly backed by an `emptyDir`.

### 10. Validate Read-Only Root Filesystem

```bash
kubectl exec hardened-test-pod -- sh -c '
echo "blocked" > /root-filesystem-test.txt
'
```

Expected result:

```text
Read-only file system
```

### 11. Validate Sensitive File Protection

```bash
kubectl exec hardened-test-pod -- \
  cat /etc/shadow
```

Expected result:

```text
Permission denied
```

### 12. Validate Restricted Kernel Operations

```bash
kubectl exec hardened-test-pod -- sh -c '
mkdir -p /tmp/mount-target
mount -t tmpfs tmpfs /tmp/mount-target
'
```

Expected result:

```text
Operation not permitted
```

### 13. Run Security Monitoring

```bash
chmod +x monitor-security.sh
./monitor-security.sh
```

The monitoring workflow reports:

- Loaded AppArmor profile state
- Recent AppArmor denials
- Kernel security events
- Pod security contexts
- seccomp configuration
- AppArmor configuration
- capability state
- `NoNewPrivs`
- hardened workload status
- CPU and memory constraints

### 14. Run Performance Assessment

```bash
chmod +x performance-test.sh
./performance-test.sh
```

The script performs equivalent filesystem operations in a normal workload and the hardened workload and records wall-clock execution time.

Metrics Server is optional. When unavailable, the runtime comparison continues without `kubectl top`.

## Tools Used

- Kubernetes
- K3s
- kubectl
- containerd
- Linux seccomp
- AppArmor
- apparmor_parser
- Linux capabilities
- Linux kernel audit events
- systemd journal
- jq
- Alpine Linux containers
- YAML
- shell scripting
- Git

## Key Skills Demonstrated

- Implemented Kubernetes Localhost seccomp profiles for syscall-level workload isolation.
- Applied mandatory access control using AppArmor.
- Migrated workload security configuration to modern Kubernetes AppArmor APIs.
- Combined independent security mechanisms into a defense-in-depth runtime architecture.
- Enforced non-root container execution.
- Eliminated unnecessary Linux capabilities.
- Disabled privilege escalation.
- Protected the container root filesystem from modification.
- Created narrowly scoped writable temporary storage.
- Configured CPU and memory resource boundaries.
- Performed positive and negative runtime security testing.
- Inspected kernel security events to verify actual enforcement.
- Built repeatable monitoring and performance validation workflows.

## Real-World Use Case

Production Kubernetes workloads process untrusted input, application data, credentials, and network traffic while sharing a host kernel with other containers. Runtime hardening reduces the impact of application compromise by constraining what a hijacked process can do after an attacker obtains code execution. seccomp limits access to sensitive kernel interfaces, AppArmor restricts files and capabilities, and Kubernetes security contexts remove privileges that ordinary application processes do not require. Together these controls reduce opportunities for privilege escalation, persistence, host manipulation, and container escape.

## Lessons Learned

- Container isolation should not depend on a single security mechanism.
- seccomp reduces kernel attack surface by restricting unnecessary system calls.
- AppArmor adds mandatory access controls independently of standard Unix permissions.
- Localhost security profiles must exist on every Kubernetes node that can schedule the workload.
- A manually maintained default-deny syscall allowlist can become brittle as container userspace and runtimes evolve.
- Non-root execution and capability dropping complement rather than replace seccomp and AppArmor.
- Read-only root filesystems are easier to operate when required writable paths are explicitly mounted.
- Negative-path tests are required to prove that runtime restrictions are genuinely enforced.
- Kernel audit events provide valuable evidence that security controls are operating beneath the Kubernetes API layer.

## Troubleshooting Log

### Kubernetes Client Present Without a Cluster

The fresh environment contained `kubectl` but no active Kubernetes context, kubeconfig, API server, or container runtime information.

Resolution:

- Bootstrapped a lightweight K3s cluster.
- Enabled kubelet seccomp-default behavior.
- Configured the user kubeconfig.
- Verified the node reached Ready state before installing security profiles.

### Kubelet seccomp Path Difference

The expected `/var/lib/kubelet/seccomp` path was not present.

Resolution:

- Identified the K3s kubelet state directory.
- Installed the profile under:

```text
/var/lib/rancher/k3s/agent/kubelet/seccomp/profiles/
```

### Fragile Default-Deny seccomp Allowlist

A manually maintained syscall allowlist can prevent a modern container from starting when libc or the runtime requires additional system calls.

Resolution:

- Used an explicit high-risk syscall deny policy.
- Preserved normal userspace behavior.
- Verified `mount` and other selected operations were denied.

### Deprecated AppArmor Kubernetes Annotation

The older container AppArmor annotation format is no longer the preferred Kubernetes configuration model.

Resolution:

- Migrated the workload to:

```yaml
securityContext:
  appArmorProfile:
    type: Localhost
```

### AppArmor Node Dependency

A Localhost AppArmor profile must already be loaded on the Kubernetes node before a workload referencing it can start.

Resolution:

- Validated profile syntax with `apparmor_parser -Q`.
- Loaded the profile with `apparmor_parser -r`.
- Verified it through `aa-status` before Pod deployment.

### Writable Root Filesystem

Leaving the entire root filesystem writable increases persistence opportunities following workload compromise.

Resolution:

- Enabled `readOnlyRootFilesystem: true`.
- Added a dedicated `/tmp` `emptyDir` for legitimate temporary writes.

### Missing Metrics Server

The environment did not expose the Kubernetes Metrics API.

Resolution:

- Treated `kubectl top` as optional.
- Added direct wall-clock workload comparison so performance validation could still complete.

## Security Validation Summary

```text
CONTROL                              RESULT
-----------------------------------  --------
seccomp kernel support               PASS
AppArmor kernel support              PASS
Localhost seccomp profile            PASS
Localhost AppArmor profile           PASS
Normal container operations          PASS
Non-root UID                         PASS
Privilege escalation disabled        PASS
All capabilities dropped             PASS
Read-only root filesystem            PASS
Writable /tmp                        PASS
/etc/shadow access                   DENIED
mount operation                      DENIED
sysfs modification                   DENIED
CPU limits                           PASS
Memory limits                        PASS
Kernel security event monitoring     PASS
```

The resulting workload retains required application functionality while reducing filesystem, privilege, capability, and kernel attack surface.
