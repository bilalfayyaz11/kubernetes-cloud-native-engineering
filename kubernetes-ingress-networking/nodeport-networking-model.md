# Kubernetes NodePort Networking

## Workload

Three Nginx replicas run with the label:

    app: web-app

## Service Selection

The NodePort Service uses:

    selector:
      app: web-app

This selector associates the Service with matching Pods.

## EndpointSlice

Kubernetes creates EndpointSlice resources containing the backend Pod IP addresses.

Conceptually:

    Client
      |
      v
    NodeIP:30080
      |
      v
    NodePort Service
      |
      v
    Service virtual IP / routing
      |
      v
    EndpointSlice
      |
      +--> web-app Pod 1
      +--> web-app Pod 2
      +--> web-app Pod 3

## NodePort Range

NodePort values normally come from the Kubernetes NodePort range.

The configured port in this implementation is:

    30080

## Docker-Driver Note

When Minikube runs with the Docker driver, the Minikube node is itself a container.

Direct access to the Minikube node IP from the host depends on host/container networking.

Therefore connectivity is validated using:

- direct node IP where reachable
- Minikube service URL as a deterministic local fallback
- in-cluster DNS and Service testing

## Service vs Pod Access

Clients should normally target the Service rather than individual Pod IP addresses.

The Service provides a stable abstraction while Pods may be replaced or rescheduled.
