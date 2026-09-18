# Kubernetes ResourceQuota Model

## Purpose

ResourceQuota limits aggregate resource consumption inside a namespace.

It does not directly control one specific container. Instead, it constrains the combined usage of objects in the namespace.

## Request Quotas

Examples:

    requests.cpu: "1"
    requests.memory: 1Gi

These limit the total requested CPU and memory across workloads in the namespace.

## Limit Quotas

Examples:

    limits.cpu: "2"
    limits.memory: 2Gi

These limit the combined configured CPU and memory limits.

## Object Count Quotas

Examples:

    pods: "10"
    services: "5"
    persistentvolumeclaims: "4"

These restrict the number of selected Kubernetes objects that may exist in the namespace.

## Admission-Time Enforcement

ResourceQuota is enforced during admission.

If creating a workload would cause the namespace to exceed a hard quota, the API request is rejected.

That means the oversized Pod is not merely left Pending.

It is normally prevented from being created.

## Resource Governance Pattern

A useful namespace-governance model is:

    Namespace
       |
       +--> ResourceQuota
       |      |
       |      +--> aggregate CPU requests
       |      +--> aggregate CPU limits
       |      +--> aggregate memory requests
       |      +--> aggregate memory limits
       |      +--> object counts
       |
       +--> workloads
              |
              +--> explicit requests
              +--> explicit limits
