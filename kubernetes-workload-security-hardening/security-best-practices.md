# Kubernetes SecurityContext Best Practices

## Essential Security Settings

1. Run containers as non-root
   - Set `runAsNonRoot: true`
   - Use explicit `runAsUser` and `runAsGroup` values where practical

2. Disable privilege escalation
   - Set `allowPrivilegeEscalation: false`

3. Use a read-only root filesystem
   - Set `readOnlyRootFilesystem: true`
   - Mount writable volumes only for paths the application actually needs

4. Drop Linux capabilities by default
   - Use `capabilities.drop: [ALL]`
   - Add back only the exact capability required by the workload

5. Use seccomp
   - Set `seccompProfile.type: RuntimeDefault`

6. Enforce Pod Security Standards
   - Use Restricted Pod Security Admission for namespaces that should enforce hardened workloads

7. Verify the live runtime state
   - Inspect `/proc/1/status`
   - Check `CapEff`
   - Check `NoNewPrivs`
   - Check `Seccomp`
   - Test restricted operations directly

## Writable Path Strategy

Applications with a read-only root filesystem may still need temporary writable directories.

Use dedicated `emptyDir` mounts for required paths such as:

- `/tmp`
- `/var/cache/nginx`
- `/var/run`

Avoid making the entire root filesystem writable just to satisfy a few runtime paths.

## Linux Capability Guidance

Capabilities should be treated as narrowly scoped privileges.

Recommended pattern:

    capabilities:
      drop:
        - ALL

Only add a capability when a concrete runtime requirement exists.

`NET_ADMIN` is powerful because it allows network administration operations such as interface creation and deletion. It should not be granted to ordinary application workloads.

## Pod Security Standards

A Restricted workload should generally include:

    runAsNonRoot: true

    allowPrivilegeEscalation: false

    capabilities:
      drop:
        - ALL

    seccompProfile:
      type: RuntimeDefault

A cluster can enforce this with namespace labels such as:

    pod-security.kubernetes.io/enforce=restricted

## Common Failure Patterns

### Non-root conflict

Problem:

    runAsNonRoot: true
    runAsUser: 0

These settings conflict.

Fix:

Use a non-root UID.

### Read-only root filesystem failure

Problem:

Application attempts to write to paths inside the container root filesystem.

Fix:

Mount writable `emptyDir`, persistent storage, or another appropriate volume only at the required paths.

### Capability missing

Problem:

A process attempts a privileged kernel operation but the required capability is absent.

Fix:

Confirm whether the capability is truly required. If it is, add only that capability and verify the live effective capability set.

### Capability declared but not effective

Do not assume the YAML declaration proves the running process received the capability.

Verify:

    grep CapEff /proc/1/status

and test the actual privileged operation.

### Pod Security Admission rejection

A Restricted namespace will reject workloads that violate the configured Pod Security Standard.

Use the admission error message to identify which field must be hardened.

## Validation Checklist

- [ ] Container runs as a non-root UID
- [ ] Privilege escalation is disabled
- [ ] Root filesystem is read-only where practical
- [ ] All unnecessary capabilities are dropped
- [ ] Added capabilities are explicitly justified
- [ ] RuntimeDefault seccomp is enabled
- [ ] Writable paths are narrowly scoped
- [ ] Pod Security Admission is configured where appropriate
- [ ] Live runtime security state is verified
- [ ] Application still functions after hardening
