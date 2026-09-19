# Kubernetes API Migration Summary

## Deployment

Old API:

    extensions/v1beta1

Current API:

    apps/v1

Important migration point:

    spec.selector must explicitly match the Pod template labels.

## Ingress

Old API:

    extensions/v1beta1

Current API:

    networking.k8s.io/v1

Important structural changes:

    serviceName
        ->
    backend.service.name

    servicePort
        ->
    backend.service.port.number

The current API also requires:

    pathType

## PodSecurityPolicy

Old API:

    policy/v1beta1 PodSecurityPolicy

Replacement:

    Pod Security Standards through Pod Security Admission namespace labels

Example:

    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted

PodSecurityPolicy is not migrated to another PodSecurityPolicy API version because the resource itself was removed.
