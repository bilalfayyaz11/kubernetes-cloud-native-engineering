# Service Selector Failure Diagnosis

## Failure

The ClusterIP Service selector was intentionally changed from:

    app: web-app

to:

    app: non-existent-backend

## Effect

The Service no longer matched the application Pods.

As a result:

    Service
      |
      v
    EndpointSlice
      |
      v
    zero ready application endpoints

The Ingress still existed and routed to the Service, but the Service had no backend Pods.

## Expected Symptom

The ingress controller may return:

    HTTP 503 Service Unavailable

because it cannot forward the request to a healthy backend.

## Troubleshooting Order

    kubectl get pods --show-labels
        |
        v
    kubectl describe service
        |
        v
    inspect Service selector
        |
        v
    kubectl get endpointslice
        |
        v
    compare Pod labels with selector

This distinguishes ingress-controller problems from backend-Service selection problems.
