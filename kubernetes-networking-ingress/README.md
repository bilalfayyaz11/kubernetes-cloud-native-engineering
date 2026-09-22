# Kubernetes Networking, Ingress, and TLS

## Overview

This implementation demonstrates Kubernetes application networking from internal Service discovery through externally routed HTTP and HTTPS traffic.

The environment was built from a fresh Ubuntu host and configured with Kubernetes, containerd, Flannel networking, application Services, an NGINX Ingress controller, path-based routing, TLS termination, HTTPS redirection, and end-to-end diagnostics.

Implemented capabilities include:

- Kubernetes cluster networking
- ClusterIP Services
- LoadBalancer Service behavior
- EndpointSlice validation
- NodePort-based ingress access
- Multi-backend routing
- Host-based routing
- Path-based routing
- TLS Secrets
- HTTPS termination
- HTTP-to-HTTPS redirection
- Certificate validation
- Service troubleshooting
- Ingress diagnostics
- Reusable verification automation

---

## Architecture

~~text
                       Client Traffic
                            |
                            v
                 +----------------------+
                 |   Ingress Controller |
                 |      HTTP / HTTPS    |
                 +----------+-----------+
                            |
              networking.local
                            |
                +-----------+-----------+
                |                       |
                | /                     | /api
                v                       v
        +---------------+       +---------------+
        | web-app-      |       | api-app-      |
        | service       |       | service       |
        | ClusterIP     |       | ClusterIP     |
        +-------+-------+       +-------+-------+
                |                       |
                v                       v
          web-app Pods              api-app Pods
          3 replicas                2 replicas
~~

---

## Environment

The environment uses:

- Ubuntu 24.04
- Kubernetes v1.36
- kubeadm
- kubelet
- kubectl
- containerd
- crictl
- Flannel CNI
- NGINX Ingress Controller
- OpenSSL
- curl

The original host did not contain an active Kubernetes cluster, so the complete networking environment was initialized before application routing was configured.

---

## Kubernetes Bootstrap

The cluster was initialized using kubeadm with:

~~text
Pod network CIDR: 10.244.0.0/16
Container runtime: containerd
CRI socket: unix:///run/containerd/containerd.sock
~~

containerd was configured with systemd cgroups and validated through the CRI interface before Kubernetes initialization.

Flannel provides Pod networking.

Because the environment contains a single node, the control-plane scheduling taint was removed so application workloads could run on the available node.

Basic ClusterIP communication was verified before application-specific networking was introduced.

---

## Application Backends

Two independent application backends were deployed.

### Web Application

~~text
Deployment: web-app
Replicas:   3
Service:    web-app-service
Type:       ClusterIP
Port:       80
~~

### API Application

~~text
Deployment: api-app
Replicas:   2
Service:    api-app-service
Type:       ClusterIP
Port:       80
~~

Both Services use label selectors to route traffic to their associated Pods.

---

## ClusterIP Networking

The main application is exposed internally through:

~~text
web-app-service
~~

ClusterIP behavior was validated using an ephemeral BusyBox client inside the cluster.

The validation confirmed:

- Service DNS resolution
- virtual Service IP routing
- Pod selection
- backend connectivity
- application response

---

## EndpointSlices

Backend discovery was verified using EndpointSlices.

Examples:

~~bash
kubectl get endpointslice \
  -l kubernetes.io/service-name=web-app-service

kubectl get endpointslice \
  -l kubernetes.io/service-name=api-app-service
~~

This confirms that each Service correctly resolves to the expected Pod addresses.

---

## LoadBalancer Service

The application was also exposed through:

~~text
web-app-loadbalancer
Type: LoadBalancer
~~

The Service remained functional inside Kubernetes and received an automatically allocated NodePort.

No external load-balancer address was assigned because this kubeadm environment does not include a cloud load-balancer implementation.

This demonstrates an important distinction:

~~text
LoadBalancer Service
        |
        +--> ClusterIP
        |
        +--> NodePort
        |
        +--> External Load Balancer
              only when supported by the environment
~~

An external address remaining unassigned in this environment does not indicate an application failure.

---

## Ingress Controller

An NGINX Ingress controller was deployed in bare-metal mode.

Its controller Service exposes HTTP and HTTPS through NodePorts.

Validation included:

~~bash
kubectl get deployment ingress-nginx-controller -n ingress-nginx
kubectl get service ingress-nginx-controller -n ingress-nginx
kubectl get ingressclass nginx
~~

The IngressClass connects application Ingress resources to the controller.

---

## Host-Based Routing

Routing is scoped to:

~~text
networking.local
~~

The Host header determines whether the Ingress rule matches.

Example request:

~~bash
curl \
  -H 'Host: networking.local' \
  http://<node-ip>:<http-nodeport>/
~~

Requests without the matching hostname do not use the configured application rule.

---

## Path-Based Routing

One Ingress resource routes traffic to different Services according to URL path.

~~text
networking.local/
        |
        +--> /      --> web-app-service
        |
        +--> /api   --> api-app-service
~~

This demonstrates how one entry point can front multiple application components.

---

## Ingress Configuration

The final Ingress configuration contains both application paths and TLS settings.

~~yaml
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - networking.local
      secretName: networking-tls
  rules:
    - host: networking.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-app-service
                port:
                  number: 80
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-app-service
                port:
                  number: 80
~~

A single Ingress owns the hostname and paths rather than creating duplicate resources for HTTP and HTTPS.

---

## TLS Implementation

A self-signed certificate was generated for:

~~text
networking.local
~~

The certificate includes:

~~text
Common Name: networking.local
Subject Alternative Name: DNS:networking.local
~~

It was stored in Kubernetes as:

~~text
Secret: networking-tls
Type: kubernetes.io/tls
~~

The private key remains local and is intentionally excluded from source control.

---

## TLS Termination

TLS terminates at the Ingress controller.

~~text
HTTPS Client
     |
     | TLS
     v
Ingress Controller
     |
     | HTTP inside cluster
     v
ClusterIP Service
     |
     v
Application Pod
~~

This allows backend applications to remain on standard internal HTTP while the ingress layer handles encrypted external traffic.

---

## HTTPS Routing

HTTPS routing was validated for both application paths.

~~text
https://networking.local/
    -> web-app-service

https://networking.local/api/
    -> api-app-service
~~

The served certificate was inspected with OpenSSL to confirm its subject, issuer, validity period, and Subject Alternative Name.

---

## HTTP to HTTPS Redirect

The Ingress enforces encrypted access using:

~~yaml
nginx.ingress.kubernetes.io/ssl-redirect: "true"
nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
~~

Plain HTTP requests return a redirect response to HTTPS.

Accepted redirect behavior includes standard redirect status codes such as:

~~text
301
302
307
308
~~

---

## Local HTTPS Validation

The host already had another process listening on TCP 8443.

To avoid interfering with that service, local HTTPS validation used:

~~text
9443 -> ingress-nginx-controller:443
~~

The port-forward was started only for the duration of verification and then terminated automatically.

---

## Certificate Validation

The served certificate was inspected with:

~~bash
openssl s_client \
  -connect 127.0.0.1:9443 \
  -servername networking.local
~~

The output was then passed to:

~~bash
openssl x509 \
  -noout \
  -subject \
  -issuer \
  -dates \
  -ext subjectAltName
~~

This confirmed that the Ingress controller was serving the expected certificate.

---

## Security Controls

Several safeguards were applied:

- TLS private keys remain outside repository artifacts
- Secret payloads are not intentionally printed into evidence files
- `.tls` is excluded from Git
- private-key extensions are blocked during packaging
- one Ingress owns each hostname/path combination
- HTTP traffic is redirected to HTTPS
- certificate hostname validation is performed
- local forwarding processes are terminated after testing

The self-signed certificate is appropriate only for controlled testing.

Production environments should use certificates issued by a trusted authority with automated certificate lifecycle management.

---

## Troubleshooting Workflow

The diagnostic workflow used across the implementation is:

~~text
Client Request
      |
      v
Ingress Controller
      |
      v
Ingress Rule
      |
      v
Service
      |
      v
EndpointSlice
      |
      v
Pod
~~

Useful commands include:

~~bash
kubectl get ingress
kubectl describe ingress web-app-ingress
kubectl get ingressclass
kubectl get services
kubectl get endpointslice
kubectl get pods --show-labels
kubectl get events
kubectl logs -n ingress-nginx \
  deployment/ingress-nginx-controller
~~

---

## Failure Isolation

Different symptoms indicate failures at different layers.

### No Service endpoints

Check:

~~bash
kubectl get endpointslice
kubectl get pods --show-labels
~~

Likely causes include selector or Pod-readiness problems.

### Service works but Ingress fails

Check:

~~bash
kubectl describe ingress web-app-ingress
kubectl logs -n ingress-nginx \
  deployment/ingress-nginx-controller
~~

### HTTPS fails

Check:

~~bash
kubectl get secret networking-tls
kubectl describe ingress web-app-ingress
openssl s_client
~~

### LoadBalancer has no external address

Verify whether the cluster actually includes a cloud or bare-metal load-balancer implementation.

A kubeadm cluster does not automatically provision one.

---

## Automated Verification

The reusable script:

~~text
scripts/test-networking-ingress.sh
~~

validates the complete traffic path.

It checks:

- LoadBalancer Service
- web Deployment
- API Deployment
- ClusterIP Services
- EndpointSlices
- Ingress
- TLS Secret
- HTTPS root routing
- HTTPS API routing
- HTTP-to-HTTPS redirect
- served certificate hostname
- Ingress controller
- IngressClass
- warning events

The script exits non-zero when a required networking check fails.

---

## Evidence

Generated operational evidence includes:

~~text
networking-environment-notes.txt
networking-environment-evidence.txt
service-type-comparison.txt
service-networking-evidence.txt
http-ingress-evidence.txt
ingress-controller-logs.txt
served-certificate-details.txt
tls-security-notes.txt
https-ingress-evidence.txt
networking-validation-report.txt
ingress-diagnostics.txt
service-endpoint-diagnostics.txt
final-networking-evidence.txt
~~

---

## Repository Structure

~~text
kubernetes-networking-ingress/
├── README.md
├── networking-environment-notes.txt
├── networking-environment-evidence.txt
├── service-type-comparison.txt
├── service-networking-evidence.txt
├── http-ingress-evidence.txt
├── ingress-controller-logs.txt
├── served-certificate-details.txt
├── tls-security-notes.txt
├── https-ingress-evidence.txt
├── networking-validation-report.txt
├── ingress-diagnostics.txt
├── service-endpoint-diagnostics.txt
├── final-networking-evidence.txt
├── manifests/
│   ├── web-app-deployment.yaml
│   ├── web-app-service.yaml
│   ├── web-app-loadbalancer.yaml
│   ├── api-app-deployment.yaml
│   └── http-ingress.yaml
└── scripts/
    └── test-networking-ingress.sh
~~

---

## Skills Demonstrated

- Kubernetes networking
- kubeadm
- containerd
- Flannel CNI
- ClusterIP Services
- LoadBalancer Services
- NodePort networking
- EndpointSlices
- Service discovery
- NGINX Ingress
- IngressClass
- host-based routing
- path-based routing
- TLS Secrets
- TLS termination
- HTTPS
- HTTP redirection
- OpenSSL certificate inspection
- curl-based network testing
- backend troubleshooting
- Ingress-controller diagnostics
- Kubernetes Events
- shell-based validation automation

---

## Operational Relevance

These techniques apply directly to:

- Kubernetes administration
- Platform engineering
- DevOps
- Site Reliability Engineering
- cloud-native infrastructure
- application delivery
- microservice routing
- production troubleshooting
- secure service exposure

The end-to-end traffic flow demonstrated is:

~~text
Application Pods
      |
      v
ClusterIP Services
      |
      v
Ingress Rules
      |
      v
TLS Termination
      |
      v
HTTP / HTTPS Clients
~~

The main outcome is the ability to expose Kubernetes applications securely, route multiple application paths through one ingress layer, validate the complete network path, and isolate failures across Service, EndpointSlice, Ingress, and TLS layers.
