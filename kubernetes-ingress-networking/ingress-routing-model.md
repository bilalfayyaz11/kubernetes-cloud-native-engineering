# Kubernetes Ingress Routing Model

## ClusterIP Backend

The application is exposed internally through:

    web-app-service

The Service selects Pods with:

    app: web-app

## Host-Based Routing

The Ingress defines two host rules:

    webapp.local
    webapp.example.com

Both hosts currently route to:

    web-app-service:80

## Request Path

Conceptually:

    HTTP Client
        |
        | Host: webapp.local
        v
    Ingress Controller
        |
        v
    Ingress Rule
        |
        v
    ClusterIP Service
        |
        v
    EndpointSlice
        |
        +--> web-app Pod
        +--> web-app Pod
        +--> web-app Pod

## Service vs Ingress

A Service provides stable networking to Kubernetes workloads.

Ingress provides HTTP/HTTPS routing rules above Services.

A common architecture is:

    Client
      |
      v
    Ingress
      |
      v
    ClusterIP Service
      |
      v
    Pods

## NodePort vs Ingress

NodePort exposes a Service through a node-level TCP port.

Ingress provides application-layer routing using HTTP concepts such as:

- hostnames
- URL paths
- TLS termination

Ingress therefore allows multiple HTTP applications to share a common entry point.

## Local Testing

The ingress controller Service is port-forwarded to:

    localhost:8080

Host-based routing is tested using explicit HTTP Host headers.

This avoids requiring permanent local DNS or `/etc/hosts` modifications.
