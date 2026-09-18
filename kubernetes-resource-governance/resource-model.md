# Kubernetes Resource Model

## CPU Requests

CPU requests are used by the Kubernetes scheduler when deciding whether a Pod can fit on a node.

Example:

    requests:
      cpu: 250m

`250m` means 250 millicores, or 0.25 CPU.

## CPU Limits

CPU limits define an upper CPU usage boundary enforced through the container runtime and Linux CPU controls.

Example:

    limits:
      cpu: 500m

`500m` means 0.5 CPU.

When a container attempts to exceed its CPU limit, CPU usage can be throttled.

## Memory Requests

Memory requests contribute to scheduling decisions and namespace quota accounting.

Example:

    requests:
      memory: 64Mi

## Memory Limits

Memory limits define the maximum memory available to the container.

Example:

    limits:
      memory: 128Mi

If the container exceeds its enforced memory limit, it may be terminated with an out-of-memory condition.

## Requests vs Limits

Requests answer:

    How much resource should Kubernetes account for when scheduling this workload?

Limits answer:

    What maximum resource boundary should be enforced for this container?

## QoS

A Pod with requests lower than its limits is typically classified as:

    Burstable

This matters during resource pressure because Kubernetes uses QoS classes as part of eviction behavior.
