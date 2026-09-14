# Advanced Kubernetes Operations

## Configuration Management

A ConfigMap was created to store non-sensitive application configuration.

A Secret was created to demonstrate Kubernetes-native handling of sensitive configuration values.

These resources separate configuration from container images and allow runtime configuration to be managed independently from application packaging.

## Health Management

A dedicated nginx Deployment was configured with:

- liveness probe
- readiness probe
- two replicas
- CPU requests and limits
- memory requests and limits

The readiness probe determines when a Pod is ready to receive traffic.

The liveness probe allows Kubernetes to detect an unhealthy container and restart it when necessary.

## Rolling Update

The Deployment image was updated from:

`nginx:1.21`

to:

`nginx:1.22`

The rollout was monitored using Kubernetes Deployment rollout controls.

The update demonstrated how Kubernetes replaces application replicas incrementally while maintaining the declared Deployment state.

## Operational Benefit

ConfigMaps, Secrets, probes, and rolling updates demonstrate how Kubernetes moves operational behavior into declarative workload definitions.

This reduces dependence on manual container lifecycle management and provides consistent application-management primitives across the cluster.
