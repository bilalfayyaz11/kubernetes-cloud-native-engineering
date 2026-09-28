# Pod Security Standards Findings

## Baseline Policy Results

- Non-privileged, non-host-level workloads were admitted.
- Privileged containers were rejected.
- hostNetwork workloads were rejected.
- hostPID and hostIPC workloads were rejected.
- hostPath volumes were rejected.
- Baseline blocked direct host-level privilege exposure without requiring the full Restricted hardening profile.

## Restricted Policy Results

- Restricted required seccomp configuration.
- Privilege escalation had to be disabled.
- Containers had to run as non-root.
- Linux capabilities had to be dropped.
- Workloads accepted by Baseline could still be rejected by Restricted.
- Fully hardened workloads remained functional when configured correctly.

## Baseline vs Restricted

Baseline provides a practical minimum security boundary that blocks known privilege-escalation paths and direct host access.

Restricted applies a stronger workload-hardening model suitable for security-sensitive production namespaces. It requires workloads to explicitly adopt controls such as non-root execution, RuntimeDefault seccomp, capability reduction, and privilege-escalation prevention.

## Production Practices

1. Pin Pod Security Standard versions for predictable admission behavior.
2. Use Restricted enforcement for security-sensitive application namespaces.
3. Test existing workloads with warn/audit modes before raising enforcement.
4. Run containers as non-root.
5. Disable privilege escalation.
6. Drop Linux capabilities unless explicitly required.
7. Use RuntimeDefault seccomp.
8. Prefer read-only root filesystems where workload design permits.
9. Provide explicit writable volumes only for paths that require them.
10. Configure health probes and resource requests/limits independently of admission controls.

## Validation

The environment proved both sides of admission control:

- intentionally unsafe workloads were rejected;
- compliant workloads were admitted;
- a production-style application remained reachable while operating under Restricted enforcement.
