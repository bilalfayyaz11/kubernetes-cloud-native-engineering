# Kubernetes LimitRange Model

## Purpose

A LimitRange defines resource policies for individual objects inside a namespace.

It can provide default requests and limits when containers omit them.

## Example Defaults

This implementation applies:

    defaultRequest:
      cpu: 100m
      memory: 64Mi

    default:
      cpu: 200m
      memory: 128Mi

## Admission-Time Mutation

The source Pod manifest contains no explicit resource configuration.

During admission, Kubernetes applies the LimitRange defaults.

Conceptually:

    Pod submitted
        |
        v
    Namespace admission
        |
        v
    LimitRange detected
        |
        v
    Missing request/limit values populated
        |
        v
    ResourceQuota evaluated
        |
        v
    Pod admitted if quota remains available

## LimitRange vs ResourceQuota

LimitRange controls individual workload defaults and boundaries.

ResourceQuota controls aggregate namespace consumption.

Together they provide:

    workload-level defaults
            +
    namespace-level budget control

This prevents unbounded resource declarations while also ensuring workloads contribute predictable values to quota accounting.
