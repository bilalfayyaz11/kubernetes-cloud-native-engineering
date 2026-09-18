# Kubernetes Network Segmentation Model

## Ingress Control

The backend database accepts TCP/5432 from:

    app=frontend

It rejects unrelated application and external namespace clients.

## Egress Control

The backend is permitted to initiate:

    TCP/80 -> frontend
    UDP/53 -> CoreDNS
    TCP/53 -> CoreDNS

Other tested external application traffic is blocked.

## Final Flow

    +-------------------+
    | Frontend          |
    | app=frontend      |
    +---------+---------+
              |
              | TCP/5432 ALLOW
              v
    +-------------------+
    | Backend Database  |
    | app=backend       |
    +-------------------+
         ^          |
         X          | TCP/80 ALLOW
         |          v
    test-client   frontend

    external-client
         |
         X TCP/5432

Backend DNS:

    backend
       |
       +--> CoreDNS UDP/TCP 53

Backend external application traffic:

    backend
       |
       X--> external-web:80

## Security Outcome

The environment moves from unrestricted east-west communication toward an explicit least-privilege model.

Only required network paths remain available.
