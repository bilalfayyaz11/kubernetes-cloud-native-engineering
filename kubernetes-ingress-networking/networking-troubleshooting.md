# Kubernetes Networking Troubleshooting

## Start with the Workload

Verify application Pods first:

    kubectl get pods
    kubectl describe pod

A networking layer cannot route successfully to unhealthy workloads.

## Verify Pod Labels

Services select Pods by labels.

Use:

    kubectl get pods --show-labels

Then compare labels against the Service selector.

## Verify the Service

Inspect:

    kubectl describe service <service>

Check:

- selector
- port
- targetPort
- Service type
- ClusterIP

## Verify EndpointSlice

Use:

    kubectl get endpointslice

If a Service has no ready endpoints, routing to the application cannot succeed.

## Verify Ingress

Inspect:

    kubectl get ingress
    kubectl describe ingress

Check:

- ingressClassName
- hostname
- path
- backend Service
- backend port
- TLS Secret references

## HTTP 503

A common ingress 503 scenario is:

    Ingress rule exists
        |
        v
    Service exists
        |
        v
    Service selector matches no Pods
        |
        v
    zero backend endpoints
        |
        v
    ingress returns 503

## DNS and Host Routing

Ingress host routing depends on the HTTP Host header.

Local testing can avoid DNS changes using:

    curl -H "Host: example.local" http://127.0.0.1:<port>

For HTTPS, SNI and hostname resolution can be tested using curl `--resolve`.

## TLS Troubleshooting

Check:

    kubectl describe secret <tls-secret>

Then inspect the served certificate with:

    openssl s_client

Verify:

- certificate subject
- Subject Alternative Name
- expiration dates
- SNI hostname selection

## NodePort Troubleshooting

With Minikube's Docker driver, direct host-to-node networking can vary.

Useful options include:

- Minikube node IP where reachable
- `minikube service <service> --url`
- in-cluster Service testing

## Recommended Troubleshooting Order

    Pods
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
    Ingress rules
      |
      v
    Controller logs
      |
      v
    DNS / Host header
      |
      v
    TLS / SNI
