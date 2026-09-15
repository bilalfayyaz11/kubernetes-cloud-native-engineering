# Istio Service Mesh

A Kubernetes service-mesh implementation demonstrating secure service-to-service communication, identity-aware access control, controlled traffic routing, resilience patterns, and mesh-level observability using Istio and Envoy.

The implementation uses the Bookinfo microservice architecture as the workload layer and applies production-relevant service-mesh controls around it.

## Architecture

~~text
                         External Client
                               |
                               v
                    Istio Ingress Gateway
                               |
                               v
                     productpage + Envoy
                       /             \
                      /               \
                     v                 v
             details + Envoy      reviews + Envoy
                                  /      |      \
                                 /       |       \
                                v        v        v
                               v1       v2       v3
                                         |
                                         v
                                  ratings + Envoy


                    Istio Control Plane
                           istiod
                              |
          +-------------------+-------------------+
          |                   |                   |
     Traffic Policy      Security Policy      Telemetry
          |                   |                   |
          v                   v                   v
   VirtualService       PeerAuthentication    Prometheus
   DestinationRule      AuthorizationPolicy   Kiali
   Retry / Timeout      STRICT mTLS           Grafana
   Fault Injection      Workload Identity     Jaeger
~~

## Capabilities Demonstrated

- Istio control-plane deployment on Kubernetes
- automatic Envoy sidecar injection
- Kubernetes native sidecar support
- Istio ingress routing
- service subsets with `DestinationRule`
- weighted traffic distribution
- HTTP header-based routing
- strict mutual TLS
- SPIFFE-based workload identity
- authorization policy enforcement
- least-request load balancing
- connection-pool limits
- outlier detection
- retries and request timeouts
- controlled latency and HTTP fault injection
- Envoy cluster, listener, and route inspection
- Istio telemetry with Prometheus
- topology and service visibility with Kiali
- Grafana mesh dashboards
- distributed tracing with Jaeger

## Technology Stack

| Component | Purpose |
|---|---|
| Kubernetes | Container orchestration |
| Istio | Service mesh control plane |
| Envoy | Data-plane proxy |
| Minikube | Local Kubernetes environment |
| Prometheus | Mesh telemetry |
| Grafana | Metrics visualization |
| Kiali | Service topology and mesh analysis |
| Jaeger | Distributed tracing |
| kubectl | Kubernetes administration |
| istioctl | Istio administration and diagnostics |

## Repository Structure

~~text
istio-service-mesh/
├── README.md
├── install/
│   └── istio-install.yaml
├── traffic-management/
│   ├── reviews-destination-rule.yaml
│   └── reviews-virtual-service.yaml
├── security/
│   ├── peer-authentication.yaml
│   └── reviews-authorization-policy.yaml
└── resilience/
    ├── reviews-advanced-destination-rule.yaml
    ├── reviews-timeout-retry.yaml
    └── reviews-fault-injection.yaml
~~

## Istio Installation

The mesh uses a resource-conscious Istio configuration suitable for a constrained Kubernetes environment.

~~bash
istioctl install \
  -f install/istio-install.yaml \
  -y
~~

Automatic injection is enabled at namespace level:

~~bash
kubectl label namespace default \
  istio-injection=enabled
~~

With modern Kubernetes releases, Istio can run Envoy using Kubernetes native sidecar semantics.

The proxy may therefore appear under `initContainers` with:

~~text
restartPolicy: Always
~~

rather than only under the traditional application container list.

## Traffic Management

### Service Subsets

The `reviews` service is divided into three subsets based on workload labels:

~~text
reviews
├── v1
├── v2
└── v3
~~

Defined in:

~~text
traffic-management/reviews-destination-rule.yaml
~~

### Weighted Traffic Routing

Default traffic is distributed between two revisions:

~~text
reviews v1  -> 50%
reviews v3  -> 50%
~~

Observed validation over 40 requests produced:

~~text
reviews v1: 21 requests
reviews v3: 19 requests
~~

This demonstrated successful probabilistic traffic distribution through Envoy.

### Header-Based Routing

Requests matching:

~~http
end-user: jason
~~

are routed to:

~~text
reviews v2
~~

Direct mesh validation produced:

~~text
10 / 10 requests routed to the expected rating-enabled path
~~

## Mutual TLS

Namespace-wide strict mTLS is enabled using `PeerAuthentication`.

~~yaml
spec:
  mtls:
    mode: STRICT
~~

The policy is defined in:

~~text
security/peer-authentication.yaml
~~

This ensures plaintext workloads outside the mesh cannot communicate directly with protected mesh workloads.

Validation included:

- successful mesh-to-mesh communication
- rejection of a non-mesh plaintext client
- Envoy TLS configuration inspection
- proxy synchronization verification

## Workload Identity and Authorization

Authorization is enforced for the reviews service using an Istio `AuthorizationPolicy`.

Only the expected Bookinfo productpage workload identity is permitted through the configured policy.

The authorization relationship is based on workload identity:

~~text
cluster.local/ns/default/sa/bookinfo-productpage
~~

This demonstrates service-to-service access control without application-level credential handling.

Configuration:

~~text
security/reviews-authorization-policy.yaml
~~

## Load Balancing and Circuit Breaking

The advanced destination policy applies:

~~yaml
loadBalancer:
  simple: LEAST_REQUEST
~~

Connection controls include:

~~yaml
connectionPool:
  tcp:
    maxConnections: 10

  http:
    http1MaxPendingRequests: 10
    http2MaxRequests: 20
    maxRequestsPerConnection: 2
~~

Unhealthy endpoints can be removed from the load-balancing pool using outlier detection:

~~yaml
outlierDetection:
  consecutive5xxErrors: 3
  interval: 10s
  baseEjectionTime: 30s
  maxEjectionPercent: 100
~~

This provides the service-mesh equivalent of circuit-breaking behavior.

Configuration:

~~text
resilience/reviews-advanced-destination-rule.yaml
~~

## Retries and Timeouts

Request resilience is configured through the `VirtualService`.

~~yaml
timeout: 3s

retries:
  attempts: 3
  perTryTimeout: 1s
  retryOn: gateway-error,connect-failure,refused-stream,unavailable
~~

Configuration:

~~text
resilience/reviews-timeout-retry.yaml
~~

These controls prevent downstream failures from causing indefinite request stalls and provide bounded retry behavior for transient failures.

## Fault Injection

Controlled service failures are introduced for selected requests.

The configuration includes:

~~text
50% probability of a 2-second delay
20% probability of an HTTP 500 abort
~~

This allows resilience behavior to be tested without modifying application code or intentionally breaking application containers.

Configuration:

~~text
resilience/reviews-fault-injection.yaml
~~

## Observability

The mesh was instrumented with the Istio observability stack.

### Prometheus

Prometheus collected Istio metrics including:

~~text
istio_requests_total
~~

Queries were used to inspect:

- total mesh request volume
- productpage request traffic
- reviews traffic by destination version
- successful request rates

### Kiali

Kiali provided service-mesh topology and health visibility across:

~~text
productpage
details
reviews
ratings
~~

### Grafana

Istio dashboards provided metric visualization for service and workload behavior.

### Jaeger

Jaeger provided distributed-tracing infrastructure for request-flow analysis across the mesh.

Traffic was generated through the ingress gateway to populate telemetry data.

## Envoy Diagnostics

Proxy synchronization was validated using:

~~bash
istioctl proxy-status
~~

Traffic configuration was inspected using:

~~bash
istioctl proxy-config cluster <pod>

istioctl proxy-config listener <pod>

istioctl proxy-config route <pod>
~~

This verifies that Istio configuration has propagated into the Envoy data plane.

## Validation

Key controls validated during implementation:

~~text
Istio control plane        VERIFIED
Ingress gateway            VERIFIED
Bookinfo microservices     VERIFIED
Envoy proxies              VERIFIED
Header routing             VERIFIED
Weighted traffic splitting VERIFIED
STRICT mTLS                VERIFIED
Authorization              VERIFIED
Least-request balancing    CONFIGURED
Connection pooling         CONFIGURED
Outlier detection          CONFIGURED
Retries and timeouts       CONFIGURED
Fault injection            VERIFIED
Prometheus telemetry       VERIFIED
Kiali                      VERIFIED
Grafana                    VERIFIED
Jaeger                     VERIFIED
Envoy configuration        INSPECTED
~~

Configuration analysis was performed with:

~~bash
istioctl analyze
~~

and proxy synchronization with:

~~bash
istioctl proxy-status
~~

## Security Model

The mesh applies multiple layers of service-to-service security:

~~text
Workload
   |
   v
Envoy Proxy
   |
   +--> STRICT mTLS
   |
   +--> workload identity
   |
   +--> AuthorizationPolicy
   |
   +--> controlled service routing
   |
   v
Destination workload
~~

This separates transport security, service identity, authorization, and application logic.

## Engineering Takeaways

This implementation demonstrates how a service mesh can move cross-cutting networking concerns out of individual applications and into a consistent infrastructure layer.

The resulting architecture provides:

- encrypted east-west communication
- workload-aware access controls
- progressive traffic routing
- controlled failure testing
- bounded retry behavior
- endpoint health isolation
- mesh-wide telemetry
- proxy-level operational visibility

These patterns are directly applicable to Kubernetes platform engineering, SRE, DevOps, and cloud-native microservice environments.

## Notes

The Prometheus, Grafana, Kiali, and Jaeger deployments used here are lightweight Istio sample integrations intended for local validation.

Production environments should separately evaluate:

- persistent telemetry storage
- high availability
- scalable Prometheus architecture
- hardened Grafana authentication
- dedicated tracing backends
- telemetry retention
- ingress TLS certificates
- production resource limits
- multi-cluster service-mesh architecture
