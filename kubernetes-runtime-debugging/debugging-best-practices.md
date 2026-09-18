# Kubernetes Runtime Debugging Best Practices

## Start with the Least Intrusive Method

Recommended progression:

1. `kubectl get`
2. `kubectl describe`
3. `kubectl logs`
4. `kubectl logs --previous`
5. `kubectl exec`
6. ephemeral debugging container
7. copied/debug Pod when necessary

## Application Images

Production application images should remain focused on running the application.

Do not add heavyweight troubleshooting tools solely for occasional debugging needs when an ephemeral debugging container can provide them separately.

## Ephemeral Containers

Use ephemeral containers when:

- the application container lacks required troubleshooting tools
- the original process must remain running
- network or process visibility is needed
- rebuilding the application image would be disruptive

## Security

- restrict access to the `pods/ephemeralcontainers` subresource
- apply least-privilege RBAC
- audit debugging activity
- use trusted debugging images
- avoid placing production secrets into debugging commands or captured evidence
- treat packet captures and process environments as potentially sensitive data

## Runtime Impact

Debugging containers share Pod-level resources and namespaces.

Heavy tools such as:

- tcpdump
- strace
- packet generators
- stress utilities

should be used carefully in production.

## Evidence

Capture useful operational evidence before cleanup:

- Pod descriptions
- events
- relevant logs
- resource state
- ephemeral-container specifications
- network observations

Do not commit credentials, secrets, tokens, private keys, or sensitive packet captures to source control.

## Cleanup

Normal workload resources should be removed after testing.

Ephemeral containers cannot be removed individually from an existing Pod. Recreate or delete the Pod when the debugging session is complete.
