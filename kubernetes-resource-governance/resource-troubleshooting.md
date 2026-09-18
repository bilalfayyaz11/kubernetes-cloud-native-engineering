# Kubernetes Resource Troubleshooting

## ResourceQuota Rejection

A workload that would exceed namespace ResourceQuota is rejected during admission.

Typical symptoms:

    Error from server (Forbidden)
    exceeded quota

Important consequence:

    The Pod may never be created.

Use:

    kubectl describe resourcequota <name> -n <namespace>

to compare current usage with hard limits.

## Scheduler Resource Failure

This is different from quota rejection.

When a Pod is admitted but no node has enough allocatable resources, the Pod usually remains Pending.

Typical event:

    FailedScheduling
    Insufficient cpu
    Insufficient memory

Use:

    kubectl describe pod <pod>
    kubectl get events

## Resource Requests

Requests affect:

- scheduler placement
- quota accounting
- Pod QoS classification

## Resource Limits

Limits define runtime ceilings.

CPU limits can result in throttling.

Memory limits can result in container termination when memory consumption exceeds the enforced boundary.

## LimitRange

LimitRange can automatically supply requests and limits for containers that omit them.

This makes namespace resource accounting more predictable.

## ResourceQuota

ResourceQuota controls aggregate namespace consumption.

Typical controls include:

- requests.cpu
- requests.memory
- limits.cpu
- limits.memory
- pods
- services
- persistentvolumeclaims

## Troubleshooting Workflow

A useful sequence is:

    kubectl get pods
        |
        v
    kubectl describe pod
        |
        v
    kubectl get events
        |
        v
    kubectl describe resourcequota
        |
        v
    kubectl describe limitrange
        |
        v
    inspect node allocatable resources
        |
        v
    adjust requests / limits / replica count

## Key Distinction

Admission failures happen before scheduling.

Scheduler failures happen after the Pod object has already been admitted.

That distinction is one of the fastest ways to narrow down resource-related Kubernetes failures.
