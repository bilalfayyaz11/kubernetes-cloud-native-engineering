# Kubernetes Rolling Update and Rollback Strategies

## Overview

This implementation demonstrates how Kubernetes Deployments manage application releases safely through rolling updates, ReplicaSet revisions, rollback workflows, health probes, and controlled availability settings.

The deployment lifecycle was exercised across multiple scenarios:

- initial multi-replica deployment
- controlled rolling updates
- conservative rollout strategy tuning
- ReplicaSet transition analysis
- rollout history inspection
- intentionally failed image update
- recovery using rollback
- targeted rollback to a specific revision
- revision history retention
- readiness and liveness probe integration
- service availability validation
- rollout troubleshooting and event inspection

The goal is to model a production-oriented deployment workflow where releases can be introduced gradually and recovered quickly when failures occur.

## Architecture

    rollout-demo namespace
    |
    +-- nginx-deployment
    |     |
    |     +-- ReplicaSet revision A
    |     +-- ReplicaSet revision B
    |     +-- ReplicaSet revision C
    |
    +-- nginx-service
    |
    +-- connectivity-check

Deployment progression:

    Healthy Revision
          |
          v
    Rolling Update
          |
          v
    New ReplicaSet
          |
          +--> Ready Pods
          |
          +--> Old ReplicaSet scaled down

Failure recovery:

    Healthy Revision
          |
          v
    Broken Image Update
          |
          v
    New Pods fail
          |
          v
    Existing healthy Pods remain
          |
          v
    kubectl rollout undo
          |
          v
    Previous healthy revision restored

## Namespace Isolation

All runtime resources were deployed into:

    rollout-demo

This keeps rollout-related resources isolated from other workloads.

## Initial Deployment

The initial Deployment used:

    replicas: 6

and the RollingUpdate strategy:

    maxUnavailable: 2
    maxSurge: 2

This allows Kubernetes to temporarily run extra Pods during an update while tolerating a controlled number of unavailable replicas.

The initial workload also defined CPU and memory requests and limits.

## Service Exposure

The application was exposed through a ClusterIP Service:

    nginx-service

The Service selector:

    app: nginx

remained stable across all revisions.

This allows ReplicaSets to change while clients continue using the same Service endpoint.

## Initial Connectivity Validation

A temporary curl-based Pod validated the Service:

    http://nginx-service

Expected result:

    HTTP 200

This established a known-good baseline before updates began.

## Rolling Update Mechanics

A Deployment update changes the Pod template.

Kubernetes then:

1. creates a new ReplicaSet
2. scales up the new ReplicaSet
3. waits for replacement Pods to become available
4. scales down the old ReplicaSet
5. repeats until the new revision owns the desired replica count

The Service continues selecting healthy Pods throughout the transition.

## First Controlled Update

The container image was updated through:

    kubectl set image deployment/nginx-deployment \
      nginx=<new-image> \
      -n rollout-demo

Progress was monitored using:

    kubectl rollout status \
      deployment/nginx-deployment \
      -n rollout-demo

ReplicaSets were inspected with:

    kubectl get replicasets \
      -n rollout-demo \
      -l app=nginx

The update successfully converged to all healthy replicas while maintaining Service connectivity.

## Conservative Update Strategy

The rollout policy was later tightened to:

    maxUnavailable: 1
    maxSurge: 1

Compared with a wider rollout window, this strategy updates capacity more gradually.

It prioritizes availability and controlled replacement over rollout speed.

The resulting Deployment was verified using:

    kubectl get deployment nginx-deployment \
      -n rollout-demo \
      -o json

## Replica Validation

The Deployment state was checked using:

    desired replicas
    updated replicas
    ready replicas
    available replicas

A completed healthy rollout should converge so that all of these values match the desired replica count.

## Failed Rollout Simulation

A deliberately invalid image tag was deployed to test failure behavior.

Example pattern:

    kubectl set image \
      deployment/nginx-deployment \
      nginx=<invalid-image> \
      -n rollout-demo

The rollout was expected to fail.

Failure state was inspected through:

    kubectl get pods
    kubectl get replicasets
    kubectl get events
    kubectl describe deployment

The failed revision created replacement Pods that could not become healthy.

## Availability During Failure

The existing healthy ReplicaSet continued serving traffic while the failed revision could not become available.

Service validation still returned:

    HTTP 200

This demonstrates an important property of properly configured rolling updates:

    failed replacement Pods do not automatically destroy all healthy capacity

## Rollback

Recovery was performed with:

    kubectl rollout undo \
      deployment/nginx-deployment \
      -n rollout-demo

The rollback restored the previous healthy Pod template.

Validation included:

- restored container image
- desired replica count
- ready replicas
- available replicas
- Service connectivity
- ReplicaSet state

## Rollout History

Deployment revisions were inspected using:

    kubectl rollout history \
      deployment/nginx-deployment \
      -n rollout-demo

Specific revisions can be inspected using:

    kubectl rollout history \
      deployment/nginx-deployment \
      -n rollout-demo \
      --revision=<revision>

Each Pod-template change creates a Deployment revision.

## Targeted Rollback

Instead of always rolling back one step, Kubernetes can restore a specific available revision:

    kubectl rollout undo \
      deployment/nginx-deployment \
      -n rollout-demo \
      --to-revision=<revision>

The target revision was discovered dynamically rather than assuming a particular revision number.

This avoids depending on revision numbers that may already have been removed.

## Revision History Limit

The Deployment was configured with:

    revisionHistoryLimit: 3

This limits how many old ReplicaSets Kubernetes keeps for rollback history.

Multiple image updates were performed and the retained old ReplicaSets were counted afterward.

This helps control historical resource growth while preserving rollback capability.

## Deployment Analysis

A reusable script:

    analyze-deployment.sh

captures:

- Deployment status
- rollout history
- ReplicaSet revisions
- Pod state
- rolling update strategy
- revision history limit

This provides a repeatable operational view during deployment troubleshooting.

## Health Probes

The final Deployment includes both readiness and liveness probes.

### Readiness Probe

The readiness probe checks:

    HTTP GET /

against container port 80.

A Pod that is not Ready should not receive normal Service traffic.

This is critical during rolling updates because Kubernetes should only count healthy replacements toward availability.

### Liveness Probe

The liveness probe also checks the HTTP endpoint.

If the container becomes unhealthy after startup, Kubernetes can restart it.

## Probe-Aware Rolling Update

After health checks were enabled, another image update was performed.

During the update, the following were sampled repeatedly:

    desired replicas
    current replicas
    updated replicas
    ready replicas
    available replicas
    unavailable replicas

Pod readiness and image versions were also monitored.

The rollout completed only after the replacement Pods became healthy.

## Service Continuity

Service connectivity was verified:

- before updates
- after successful updates
- during the deliberately failed rollout
- after rollback
- after probe-aware rollout

Expected response:

    HTTP 200

This validates the deployment process from the client perspective rather than relying only on controller status.

## ReplicaSet Analysis

ReplicaSets were inspected with their revision metadata.

Useful fields include:

    deployment.kubernetes.io/revision

and:

    desired replicas
    current replicas
    ready replicas
    image

This helps correlate Deployment history with actual controller resources.

## Troubleshooting a Stuck Rollout

Useful commands include:

    kubectl rollout status \
      deployment/nginx-deployment \
      -n rollout-demo

    kubectl describe deployment \
      nginx-deployment \
      -n rollout-demo

    kubectl get pods \
      -n rollout-demo \
      -l app=nginx

    kubectl get events \
      -n rollout-demo \
      --sort-by=.metadata.creationTimestamp

Common causes include:

- invalid image tags
- image pull failures
- failed readiness probes
- insufficient node resources
- container startup failures
- incorrect resource limits

## Troubleshooting Failed Pods

Inspect waiting or termination reasons:

    kubectl get pods \
      -n rollout-demo \
      -l app=nginx \
      -o json

Typical failure states may include:

    ImagePullBackOff
    ErrImagePull
    CrashLoopBackOff

The underlying Pod events should always be reviewed before modifying the Deployment.

## Resource Troubleshooting

Resource configuration can be inspected with:

    kubectl get deployment nginx-deployment \
      -n rollout-demo \
      -o json

Node capacity can be viewed using:

    kubectl get nodes

Metrics can optionally be queried using:

    kubectl top nodes

The Metrics API may not be installed in every local cluster.

Its absence does not prevent rolling updates from functioning.

## Deployment Conditions

Controller conditions can be inspected with:

    kubectl get deployment nginx-deployment \
      -n rollout-demo \
      -o json

Important conditions include:

    Available
    Progressing

These help determine whether a rollout is healthy, progressing, or stalled.

## Rollout Monitoring

Useful operational commands:

    kubectl rollout status deployment/nginx-deployment -n rollout-demo

    kubectl rollout history deployment/nginx-deployment -n rollout-demo

    kubectl get replicasets -n rollout-demo -l app=nginx

    kubectl get pods -n rollout-demo -l app=nginx -o wide

## Evidence Files

The implementation captures operational evidence including:

    rollout-history-after-first-update.txt
    deployment-after-first-update.txt
    replicasets-after-first-update.txt

    rollout-history-after-conservative-update.txt
    deployment-after-conservative-update.txt

    failed-rollout-events.txt
    failed-rollout-deployment.txt
    rollout-history-before-rollback.txt

    rollout-history-after-rollback.txt
    replicasets-after-rollback.txt
    deployment-after-rollback.txt

    rollout-history-revision-limit.txt
    replicasets-revision-limit.txt
    deployment-revision-analysis.txt

    rollout-history-after-probes.txt
    deployment-probe-state.yaml
    replicasets-after-probes.txt

    final-deployment-analysis.txt
    final-rollout-history.txt
    final-replicasets.txt
    final-pods.txt
    final-events.txt
    deployment-conditions.json
    deployment-resources.json
    final-service.yaml
    final-deployment.yaml
    rollout-tree.txt

## Technologies

- Kubernetes
- K3s
- kubectl
- Deployments
- ReplicaSets
- Pods
- Services
- RollingUpdate strategy
- rollout history
- rollback
- readiness probes
- liveness probes
- resource requests and limits
- Bash
- jq
- curl

## Engineering Skills Demonstrated

- Kubernetes Deployment management
- rolling update strategy design
- availability-aware release management
- ReplicaSet lifecycle analysis
- Deployment revision management
- targeted rollback
- failure simulation
- recovery validation
- revision retention
- readiness probe integration
- liveness probe integration
- Kubernetes event analysis
- resource troubleshooting
- rollout status monitoring
- service continuity validation
- zero-downtime deployment concepts

## Operational Model

A production-style release workflow can be represented as:

    Release N
        |
        v
    Update Deployment
        |
        v
    New ReplicaSet
        |
        +--> replacement Pod starts
        |
        +--> readiness succeeds
        |
        +--> Service receives new endpoint
        |
        +--> old Pod removed
        |
        v
    Release N+1

If the new revision fails:

    New Revision
        |
        v
    Pods fail readiness / image pull
        |
        v
    Healthy old Pods remain available
        |
        v
    Rollback
        |
        v
    Previous ReplicaSet restored

## Key Takeaways

- Rolling updates replace workloads gradually instead of all at once.
- `maxUnavailable` controls how much existing capacity may disappear during an update.
- `maxSurge` controls temporary additional capacity.
- Conservative values prioritize availability over deployment speed.
- Every Pod-template change creates a Deployment revision.
- ReplicaSets represent those historical revisions.
- Failed image updates should be diagnosed before forcing further changes.
- Rollback is a normal operational recovery mechanism.
- Targeted rollback is useful when several revisions exist.
- `revisionHistoryLimit` controls how much rollback history is retained.
- Readiness probes are essential to safe traffic transitions.
- Liveness probes provide runtime recovery after startup.
- Service-level connectivity should be tested throughout a rollout.
- Kubernetes events are one of the most valuable rollout troubleshooting sources.
- Production deployment validation should include both successful and failed scenarios.
