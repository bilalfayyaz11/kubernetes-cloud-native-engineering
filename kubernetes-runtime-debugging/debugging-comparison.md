# Kubernetes Debugging Methods Comparison

## kubectl logs
Use first when the application is producing useful stdout/stderr output.

Best for:
- application errors
- startup failures
- crash investigation
- previous container output with `--previous`

Limitations:
- only shows what the application emits

## kubectl describe
Use for Kubernetes-level configuration and lifecycle diagnosis.

Best for:
- scheduling failures
- image pull failures
- probe failures
- volume mount issues
- Pod events

Limitations:
- does not provide deep in-process application visibility

## kubectl exec
Use for quick investigation inside a running container.

Best for:
- filesystem inspection
- environment variables
- configuration files
- simple connectivity tests

Limitations:
- depends on tools already present in the application image
- minimal production images may lack debugging utilities

## Ephemeral Containers
Use when the target container is running but lacks diagnostic tooling.

Best for:
- production-style troubleshooting
- network inspection
- process inspection
- minimal/distroless workloads
- multi-container Pods

Advantages:
- keeps debugging tooling separate from the application image
- avoids rebuilding the workload solely for troubleshooting
- can target a running container

Limitations:
- requires appropriate Kubernetes API support and RBAC
- ephemeral containers are intended for troubleshooting, not permanent workload functionality

## Debug Pod / Copy-to Debugging
Use when the original Pod cannot be modified with an ephemeral container or when a copied workload is safer.

Best for:
- altered command/entrypoint testing
- filesystem inspection with modified container configuration
- environments where ephemeral-container access is restricted
