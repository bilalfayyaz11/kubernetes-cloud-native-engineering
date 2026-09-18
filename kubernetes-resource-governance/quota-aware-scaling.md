# Quota-Aware Kubernetes Scaling

## Deployment Resource Footprint

Each `web-app` replica requests:

    cpu: 100m
    memory: 32Mi

and is limited to:

    cpu: 200m
    memory: 64Mi

For three replicas, the Deployment contributes:

    CPU requests:    300m
    Memory requests: 96Mi
    CPU limits:      600m
    Memory limits:   192Mi

## Scaling and ResourceQuota

A Deployment may request more replicas than the namespace budget can support.

The Deployment controller updates the desired replica count, but Pod creation still passes through Kubernetes admission.

When a new Pod would exceed ResourceQuota:

    Deployment
        |
        v
    ReplicaSet
        |
        v
    Create Pod
        |
        v
    Admission control
        |
        +--> quota available -> Pod admitted
        |
        +--> quota exceeded -> Pod creation rejected

This means the Deployment may show a desired replica count that is higher than the number of Pods actually created.

## Important Distinction

Quota rejection differs from scheduler resource pressure.

### ResourceQuota failure

The Pod creation request is rejected at admission time.

Typical evidence:

    FailedCreate
    exceeded quota

### Scheduler resource shortage

The Pod object exists but remains Pending because no node can satisfy the resource request.

Typical evidence:

    FailedScheduling
    Insufficient cpu
    Insufficient memory

Understanding this difference is essential when troubleshooting Kubernetes scaling failures.
