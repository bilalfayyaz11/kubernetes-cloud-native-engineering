# Kubernetes Kernel Hardening

Runtime security implementation for Kubernetes workloads using Linux kernel enforcement mechanisms and restrictive container security contexts.

The implementation combines custom Seccomp syscall filtering, AppArmor mandatory access control, non-root execution, capability removal, read-only filesystems, restricted credential exposure, and automated runtime verification.

## Security Objectives

The workload is designed around several complementary controls:

- reduce the syscall attack surface with Seccomp
- enforce filesystem and process boundaries with AppArmor
- prevent privileged execution paths
- eliminate unnecessary Linux capabilities
- run application processes as a non-root identity
- prevent writes to the container root filesystem
- avoid unnecessary Kubernetes API credentials
- preserve explicitly required writable runtime paths
- verify controls from inside the running container
- continuously evaluate the deployed security configuration with executable checks

## Architecture

    Kubernetes workload
          |
          +-- Custom Seccomp profile
          |     |
          |     +-- syscall allowlist
          |     +-- default deny through SCMP_ACT_ERRNO
          |
          +-- Custom AppArmor profile
          |     |
          |     +-- filesystem restrictions
          |     +-- sensitive-file protection
          |     +-- dangerous capability restrictions
          |
          +-- Container security context
          |     |
          |     +-- non-root UID/GID
          |     +-- privilege escalation disabled
          |     +-- read-only root filesystem
          |     +-- all capabilities dropped
          |
          +-- Pod security controls
          |     |
          |     +-- ServiceAccount token automount disabled
          |     +-- controlled writable emptyDir volumes
          |
          +-- Automated verification
                |
                +-- runtime Seccomp inspection
                +-- runtime AppArmor inspection
                +-- filesystem tests
                +-- privilege checks
                +-- functional service validation

## Seccomp Enforcement

A custom Localhost Seccomp profile uses a syscall allowlist and denies syscalls outside the approved set with:

    SCMP_ACT_ERRNO

The workload declares:

    seccompProfile:
      type: Localhost
      localhostProfile: profiles/restricted-profile.json

Runtime verification inspects `/proc/self/status` and confirms that the container operates in Seccomp filter mode.

This provides evidence of enforcement rather than relying only on manifest configuration.

## AppArmor Enforcement

A custom AppArmor policy named:

    k8s-restricted-app

is loaded on the Kubernetes node and attached through the container security context:

    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-restricted-app

The policy restricts access to sensitive locations and dangerous kernel capabilities while permitting the filesystem and network operations required by the workload.

Runtime validation checks:

    /proc/self/attr/current

to confirm that the container is actually executing under the expected AppArmor profile.

## Container Hardening

The application runs with a restrictive security context including:

    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true

All Linux capabilities are removed:

    capabilities:
      drop:
        - ALL

Writable paths required by the application are explicitly provided through `emptyDir` volumes instead of making the root filesystem writable.

## Kubernetes Credential Reduction

The workload disables automatic ServiceAccount credential injection:

    automountServiceAccountToken: false

Runtime validation verifies that the standard ServiceAccount token path is absent from the container.

This reduces unnecessary exposure of Kubernetes API credentials to workloads that do not require them.

## Defense in Depth

Seccomp and AppArmor address different parts of the runtime attack surface.

Seccomp limits which system calls a process can request from the kernel.

AppArmor constrains access to files, capabilities, and other operating-system resources.

Container security controls further reduce privilege through non-root execution, capability removal, privilege-escalation prevention, and a read-only root filesystem.

These controls are applied together so that compromise of one boundary does not automatically remove the others.

## Runtime Security Tests

The validation process checks both configuration and runtime behavior.

Tests include:

- Kubernetes API availability
- workload replica readiness
- custom Seccomp declaration
- Seccomp filter mode
- Seccomp filter presence
- AppArmor runtime confinement
- non-root UID
- privilege-escalation prevention
- Linux capability removal
- read-only root filesystem enforcement
- controlled `/tmp` write access
- sensitive-file access denial
- mount-operation denial
- ServiceAccount token absence
- application service functionality

The security verifier returns a non-zero exit status when a required control fails, allowing the checks to be incorporated into automated validation workflows.

## Compliance Validation

A separate compliance check evaluates the workload against a concise set of runtime security requirements:

| Control | Expected State |
| --- | --- |
| Seccomp | Filtering active |
| AppArmor | Custom profile active |
| User | Non-root UID |
| Linux capabilities | All dropped |
| Privilege escalation | Disabled |
| Root filesystem | Read-only |
| ServiceAccount token | Automount disabled |

The resulting evidence provides both human-readable output and machine-readable security metadata.

## Repository Structure

    kubernetes-kernel-hardening/
    |
    +-- README.md
    |
    +-- manifests/
    |   +-- hardened-web-config.yaml
    |   +-- hardened-web-deployment.yaml
    |   +-- hardened-web-service.yaml
    |   +-- hardened-client.yaml
    |
    +-- profiles/
    |   +-- restricted-profile.json
    |   +-- k8s-restricted-app
    |
    +-- scripts/
    |   +-- verify-security.sh
    |   +-- compliance-check.sh
    |
    +-- evidence/
        +-- seccomp-validation.txt
        +-- apparmor-validation.txt
        +-- combined-hardening-validation.txt
        +-- security-verification-results.txt
        +-- compliance-check-results.txt
        +-- apparmor-denials.txt
        +-- hardened-workload-security-context.json
        +-- hardened-workload-evidence.yaml
        +-- hardened-service-evidence.yaml
        +-- runtime-security-evidence.txt
        +-- kernel-hardening-summary.json

## Skills Demonstrated

- Kubernetes workload security
- Linux kernel security
- Seccomp syscall filtering
- AppArmor mandatory access control
- Kubernetes SecurityContext configuration
- container privilege reduction
- Linux capability management
- read-only filesystem design
- ServiceAccount credential minimization
- runtime security validation
- security control automation
- defense-in-depth architecture
- security evidence collection
