# Open Kubernetes Pod Networking Baseline

## Workloads

The environment contains:

    frontend
    backend
    test-client
    external-client

The backend listens on:

    TCP/5432

## Namespaces

Trusted application namespace:

    network-segmentation

External test namespace:

    external-segmentation

## Baseline

Before any NetworkPolicy selects the backend Pod, connectivity is unrestricted by Kubernetes NetworkPolicy.

The following communication paths are tested:

    frontend -> backend
    test-client -> backend
    external-client -> backend

Testing is performed using both:

- backend Pod IP
- Kubernetes Service DNS

## Service Path

    Client Pod
       |
       v
    backend-db Service
       |
       v
    EndpointSlice
       |
       v
    backend Pod :5432

## Security Implication

Without isolation policy, unrelated workloads may be able to initiate connections to sensitive application tiers.

NetworkPolicy can reduce this east-west attack surface by explicitly defining allowed communication paths.
