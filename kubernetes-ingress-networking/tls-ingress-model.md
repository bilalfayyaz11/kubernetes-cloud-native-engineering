# Kubernetes TLS Ingress Model

## Purpose

TLS termination allows clients to connect to an ingress endpoint using HTTPS while the ingress controller routes traffic to internal Kubernetes Services.

## Request Flow

    HTTPS Client
        |
        | TLS + SNI hostname
        v
    Ingress Controller
        |
        +--> selects TLS Secret
        |
        +--> terminates TLS
        |
        +--> evaluates hostname/path rule
        |
        v
    ClusterIP Service
        |
        v
    EndpointSlice
        |
        v
    Application Pod

## TLS Secrets

Kubernetes TLS Secrets use:

    type: kubernetes.io/tls

and contain:

    tls.crt
    tls.key

Private keys should not be stored in Git repositories.

## Hostname Certificates

This implementation uses separate certificates for:

    webapp.local
    webapp.example.com

Each certificate contains a Subject Alternative Name matching its hostname.

## SNI

Server Name Indication allows the client to identify the requested hostname during TLS negotiation.

The ingress controller uses the hostname to select the appropriate certificate.

## HTTP to HTTPS Redirect

The TLS Ingress enables:

    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

Plain HTTP requests should therefore receive an HTTP redirect response pointing to HTTPS.

## Self-Signed Certificates

Self-signed certificates are suitable for local demonstration and testing.

Production systems should use certificates issued by a trusted Certificate Authority or an automated certificate management system.

## Local Validation

HTTP is forwarded to:

    localhost:8080

HTTPS is forwarded to:

    localhost:9443

The HTTPS port differs from the common 8443 test port because that port was already occupied on the host.

Hostname routing is tested without modifying `/etc/hosts` by using curl host resolution and explicit SNI.
