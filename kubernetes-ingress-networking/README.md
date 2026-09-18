# Kubernetes Ingress Networking

## Overview

This implementation demonstrates Kubernetes application networking from workload exposure through encrypted ingress traffic.

It covers:

- multi-replica web workloads
- ConfigMap-backed web content
- NodePort Services
- ClusterIP Services
- Service selectors
- EndpointSlice discovery
- in-cluster DNS
- host-based HTTP routing
- Kubernetes Ingress
- TLS termination
- Kubernetes TLS Secrets
- Subject Alternative Name certificates
- Server Name Indication
- HTTP-to-HTTPS redirects
- backend failure simulation
- Service selector troubleshooting
- ingress controller diagnostics
- end-to-end connectivity validation

## Architecture

```text
                    External Client
                          |
                  HTTP / HTTPS
                          |
                          v
                +------------------+
                | Ingress          |
                | Controller       |
                +--------+---------+
                         |
              Host / Path Routing
                         |
                         v
                +------------------+
                | ClusterIP        |
                | Service          |
                +--------+---------+
                         |
                         v
                 +---------------+
                 | EndpointSlice |
                 +-------+-------+
                         |
              +----------+----------+
              |          |          |
              v          v          v
           Pod 1      Pod 2      Pod 3
```

A separate NodePort path was also validated:

```text
Client
  |
  v
NodePort :30080
  |
  v
Service
  |
  v
EndpointSlice
  |
  v
Web Pods
```

## Repository Structure

```text
kubernetes-ingress-networking/
├── README.md
├── .gitignore
├── web-app-deployment.yaml
├── nodeport-service.yaml
├── clusterip-service.yaml
├── web-app-ingress.yaml
├── web-app-ingress-tls.yaml
├── nodeport-networking-model.md
├── ingress-routing-model.md
├── tls-ingress-model.md
├── service-selector-failure.md
├── networking-troubleshooting.md
├── test-networking.sh
└── evidence/
```

## Environment

Validated using:

- Ubuntu Linux
- Docker
- Minikube
- containerd
- kubectl
- Kubernetes networking API
- Minikube ingress addon
- curl
- OpenSSL
- jq
- netcat

## Namespace

Application resources were isolated in:

```text
ingress-networking
```

## Web Application

The application consists of three Nginx replicas.

Application labels:

```yaml
app: web-app
```

The deployment uses:

```text
nginx:alpine
```

rather than relying on an older pinned Nginx image.

## ConfigMap-Backed Content

Application HTML was provided through a ConfigMap and mounted into:

```text
/usr/share/nginx/html
```

This separates application configuration/content from the container image.

## Resource Controls

The web containers define CPU and memory requests and limits.

This keeps workload resource behavior predictable while testing networking components.

## NodePort Service

The first exposure model uses:

```yaml
type: NodePort
```

with:

```text
nodePort: 30080
```

The Service selects:

```yaml
app: web-app
```

## NodePort Request Path

```text
Client
  |
  v
NodeIP:30080
  |
  v
NodePort Service
  |
  v
EndpointSlice
  |
  v
Application Pods
```

## Minikube Docker Driver Consideration

With the Minikube Docker driver, the Minikube node itself runs as a container.

Direct host access to the node IP can vary by environment.

NodePort connectivity was therefore tested using:

- the Minikube node IP where available
- `minikube service --url`
- in-cluster Service access

This provides a more deterministic validation strategy.

## ClusterIP Service

Ingress traffic targets an internal ClusterIP Service:

```text
web-app-service
```

The Service exposes:

```text
port: 80
targetPort: 80
```

and selects the same web application Pods.

## EndpointSlice

EndpointSlice was used instead of relying only on the older Endpoints API.

The Service resolved to three ready backend endpoints.

Conceptually:

```text
Service
   |
   v
EndpointSlice
   |
   +--> Pod IP 1
   +--> Pod IP 2
   +--> Pod IP 3
```

## In-Cluster Service Discovery

A temporary client Pod verified access through Kubernetes DNS:

```text
http://web-app-service
```

and:

```text
http://web-app-nodeport
```

This validates the Service abstraction independently from external ingress access.

## Ingress

Host-based HTTP routing was created using:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
```

The ingress class is:

```text
nginx
```

## Host Rules

Two hosts were configured:

```text
webapp.local
webapp.example.com
```

Both route to:

```text
web-app-service:80
```

## HTTP Request Flow

```text
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
    v
Application Pod
```

## Service vs Ingress

A Kubernetes Service provides stable connectivity to workloads.

Ingress provides application-layer HTTP/HTTPS routing above Services.

Typical architecture:

```text
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
```

## NodePort vs Ingress

NodePort exposes a Service through a TCP port on cluster nodes.

Ingress supports higher-level routing capabilities including:

- HTTP hostnames
- paths
- TLS
- shared entry points
- redirects

Ingress is therefore more suitable when several HTTP applications need coordinated external access.

## Local Ingress Testing

The ingress controller was locally forwarded to:

```text
HTTP  -> localhost:8080
HTTPS -> localhost:9443
```

Port 9443 was used for HTTPS because port 8443 was already occupied on the host.

HTTP hostname routing was tested using explicit Host headers rather than permanently modifying `/etc/hosts`.

Example:

```bash
curl \
  -H "Host: webapp.local" \
  http://127.0.0.1:8080
```

## TLS Certificates

Self-signed TLS certificates were generated for local validation.

The certificates include Subject Alternative Names for:

```text
webapp.local
webapp.example.com
```

Using SAN values is important because modern TLS clients validate hostname identity against certificate SAN entries.

## Kubernetes TLS Secrets

TLS material was loaded into Kubernetes Secrets of type:

```text
kubernetes.io/tls
```

Each TLS Secret contains:

```text
tls.crt
tls.key
```

The private key values were not captured in evidence.

## TLS Secret Names

The Ingress references:

```text
webapp-local-tls
webapp-example-tls
```

## TLS Ingress

The HTTPS Ingress maps:

```text
webapp.local
    |
    +--> webapp-local-tls

webapp.example.com
    |
    +--> webapp-example-tls
```

Both route to the same internal application Service.

## TLS Request Path

```text
HTTPS Client
     |
     | SNI hostname
     v
Ingress Controller
     |
     +--> select TLS Secret
     |
     +--> terminate TLS
     |
     +--> evaluate host/path
     |
     v
ClusterIP Service
     |
     v
Application Pod
```

## Server Name Indication

SNI enables the client to provide the requested hostname during TLS negotiation.

The ingress controller can then select the certificate associated with that hostname.

Certificate selection was verified separately for:

```text
webapp.local
webapp.example.com
```

## Certificate Verification

The certificate served by the ingress controller was inspected using OpenSSL.

Validation included:

- subject
- issuer
- validity dates
- Subject Alternative Name
- SNI hostname selection

## HTTP to HTTPS Redirect

The TLS ingress enables:

```yaml
nginx.ingress.kubernetes.io/ssl-redirect: "true"
nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

Plain HTTP requests therefore redirect toward HTTPS.

Redirect response headers were captured as evidence.

## HTTPS Testing

HTTPS requests were tested locally using hostname-aware resolution.

Conceptually:

```text
webapp.local -> 127.0.0.1:9443
```

with the correct SNI hostname maintained.

Because the certificates are self-signed, certificate trust verification was intentionally bypassed for local connectivity testing.

## Private-Key Handling

TLS private keys were treated as temporary runtime material.

Controls included:

- restrictive local permissions
- exclusion through `.gitignore`
- no private-key evidence capture
- local deletion after Kubernetes Secret creation

Private key material is not intended for the Git repository.

## Broken Service Selector Scenario

The ClusterIP Service selector was intentionally changed from:

```text
app: web-app
```

to:

```text
app: non-existent-backend
```

## Failure Effect

Because no Pods matched the broken selector:

```text
Service
   |
   v
EndpointSlice
   |
   v
0 ready backends
```

The Ingress continued to route to the Service, but the Service had no healthy application endpoints.

This can result in:

```text
HTTP 503 Service Unavailable
```

## Root Cause Analysis

The failure was diagnosed by comparing:

- Pod labels
- Service selector
- EndpointSlice entries
- Ingress backend configuration

A useful sequence is:

```text
kubectl get pods --show-labels
        |
        v
kubectl describe service
        |
        v
compare selector
        |
        v
kubectl get endpointslice
```

## Service Recovery

The correct selector was restored:

```yaml
selector:
  app: web-app
```

After reconciliation, the Service again obtained three ready endpoints.

HTTP and HTTPS connectivity were then revalidated.

## Ingress 503 Troubleshooting

A useful mental model is:

```text
Ingress exists
    |
    v
Service exists
    |
    v
Service selector incorrect
    |
    v
No EndpointSlice backends
    |
    v
Ingress has nowhere to forward request
    |
    v
503
```

## Comprehensive Validation

The repository includes:

```text
test-networking.sh
```

It validates:

- NodePort reachability
- HTTP Ingress
- HTTPS Ingress
- TLS certificate subject
- backend endpoint count

The script reports PASS/FAIL results without requiring interactive input.

## Networking Troubleshooting Order

A practical investigation order is:

```text
Pods
  |
  v
Pod readiness
  |
  v
Pod labels
  |
  v
Service selector
  |
  v
EndpointSlice
  |
  v
Service ports
  |
  v
Ingress rules
  |
  v
Ingress controller
  |
  v
Controller logs
  |
  v
Host / DNS configuration
  |
  v
TLS / SNI
```

## Common Failure Types

### Application Failure

Pods themselves are unhealthy.

Check:

```text
kubectl get pods
kubectl describe pod
kubectl logs
```

### Service Selection Failure

The Service exists but matches no Pods.

Check:

```text
kubectl describe service
kubectl get pods --show-labels
kubectl get endpointslice
```

### Ingress Routing Failure

The Service is healthy but hostname or path configuration is incorrect.

Check:

```text
kubectl describe ingress
```

### Controller Failure

Ingress resources exist but the controller is unhealthy.

Check:

```text
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx
```

### DNS / Host Failure

The client is not sending the expected hostname.

Test explicitly with an HTTP Host header or curl hostname resolution.

### TLS Failure

Verify:

- Secret existence
- certificate subject
- SAN values
- expiration
- SNI selection

## Evidence

Evidence captured during the implementation includes:

- web Pod state
- application content
- NodePort Service configuration
- Service structure
- NodePort EndpointSlices
- ClusterIP Service configuration
- DNS resolution
- backend EndpointSlices
- ingress class
- ingress routing rules
- HTTP responses
- unknown-host behavior
- controller logs
- TLS Secret metadata
- TLS certificate SANs
- TLS ingress configuration
- HTTPS responses
- HTTP redirect headers
- served certificate details
- broken Service selector state
- missing endpoint state
- recovery results
- comprehensive networking test
- final resource inventory
- final Kubernetes events

## Cleanup

Runtime application resources were isolated in one namespace.

Cleanup:

```bash
kubectl delete namespace ingress-networking
```

Temporary local port-forward processes were stopped before cleanup.

Local TLS certificate and private-key material was also removed.

## Skills Demonstrated

- Kubernetes Deployments
- ConfigMaps
- Services
- NodePort
- ClusterIP
- Kubernetes DNS
- EndpointSlice
- service selectors
- ingress classes
- Kubernetes Ingress
- hostname routing
- TLS termination
- Kubernetes TLS Secrets
- OpenSSL
- SAN certificates
- SNI
- HTTPS routing
- HTTP redirects
- ingress controller validation
- Service backend troubleshooting
- EndpointSlice diagnostics
- HTTP 503 root-cause analysis
- network evidence capture

## Real-World Use Cases

These patterns apply to:

- web applications
- REST APIs
- AI inference endpoints
- internal platforms
- multi-service applications
- shared ingress gateways
- staging environments
- Kubernetes developer platforms
- HTTPS application exposure

## Key Lessons

- Services provide stable networking over dynamic Pods.
- Service selectors must match Pod labels exactly.
- EndpointSlices expose the actual Service backend state.
- NodePort and Ingress solve different exposure problems.
- Ingress routes HTTP traffic using hostname and path rules.
- ClusterIP Services are natural backends for Ingress.
- TLS can terminate at the ingress controller.
- SNI enables multiple TLS hostnames at one ingress entry point.
- SAN values are important for modern certificate hostname validation.
- Private keys should never be committed to Git.
- An Ingress can be healthy while its backend Service has no endpoints.
- A 503 can therefore be a Service-selection problem rather than an ingress-controller problem.
- Troubleshooting from Pods upward through Service, EndpointSlice, and Ingress gives a reliable diagnostic path.
