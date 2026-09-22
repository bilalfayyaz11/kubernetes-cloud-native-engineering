# Kubernetes Scheduling Policies

## Overview

This implementation demonstrates advanced Kubernetes scheduling control across a three-node cluster using node affinity, taints and tolerations, pod affinity, pod anti-affinity, scheduler diagnostics, topology constraints, and rollout-aware workload placement.

The environment was built from a fresh Ubuntu host using a lightweight multi-node kind cluster:

    1 control-plane node
    2 worker nodes
    3 total hostname topology domains

The implementation validates both successful placement and deliberate scheduling failure scenarios so that scheduler behavior can be observed directly rather than inferred.

## Architecture

    +-------------------------------------------------------+
    |                Kubernetes Scheduler                   |
    +----------------------+--------------------------------+
                           |
              +------------+-------------+
              |                          |
              v                          v
    +-------------------+      +-------------------+
    | Worker 1          |      | Worker 2          |
    | tier=database     |      | tier=web          |
    | disk=ssd          |      | disk=hdd          |
    |                   |      |                   |
    | dedicated=        |      | no custom taint   |
    | database:         |      |                   |
    | NoSchedule        |      |                   |
    +-------------------+      +-------------------+
              ^
              |
              |
    +-----------------------------+
    | Control Plane               |
    | default control-plane       |
    | NoSchedule taint            |
    +-----------------------------+

All three nodes provide independent:

    kubernetes.io/hostname

topology domains for affinity and anti-affinity evaluation.

## Environment

Host environment:

    Ubuntu 24.04 LTS
    Docker Engine
    kubectl
    kind

Kubernetes topology:

    scheduling-policy-control-plane
    scheduling-policy-worker
    scheduling-policy-worker2

Kubernetes version:

    v1.36.1

## Worker Classification

The first worker was configured as a database-oriented node:

    tier=database
    disk=ssd
    scheduling.demo/node=worker1

The second worker was configured as a web-oriented node:

    tier=web
    disk=hdd
    scheduling.demo/node=worker2

These labels provide explicit scheduling metadata that workloads can consume through node affinity.

## Required Node Affinity

The `database-app` workload uses:

    requiredDuringSchedulingIgnoredDuringExecution

with two required expressions:

    tier=database
    disk=ssd

Two replicas were deployed.

Both replicas were verified on the same intended node:

    scheduling-policy-worker

This demonstrates strict placement behavior: nodes that do not satisfy the complete expression are removed from the scheduler's eligible-node set.

## Preferred Node Affinity

The `web-app` workload demonstrates:

    preferredDuringSchedulingIgnoredDuringExecution

Its strongest preference is:

    tier=web
    weight=100

A secondary preference is:

    disk=ssd
    weight=50

Unlike required affinity, these rules influence scheduler scoring rather than making a node mandatory.

The preferred web worker was temporarily cordoned and the deployment was scaled.

The additional replica still scheduled successfully on another eligible node.

This validated the distinction between:

    required affinity
        hard scheduling constraint

and:

    preferred affinity
        scheduler scoring preference

## Taints and Tolerations

The database worker was isolated with:

    dedicated=database:NoSchedule

This prevents workloads without an appropriate toleration from being scheduled on that node.

A negative test was created with a Pod explicitly targeting the database worker but without the required toleration.

Observed state:

    Phase: Pending
    Node: unassigned

The scheduler reported the untolerated taint as the scheduling blocker.

A second workload included:

    key=dedicated
    value=database
    effect=NoSchedule

The workload successfully scheduled onto the tainted database worker.

This validates both sides of the mechanism:

    taint
        repels workloads

    toleration
        permits an otherwise blocked workload to become eligible

A toleration does not itself force placement onto a node; another placement mechanism is still needed when deterministic node selection is required.

## Pod Affinity

The frontend workload uses preferred pod affinity to favor co-location with:

    app=database-tolerant

using:

    topologyKey=kubernetes.io/hostname

The database workload was already running on the database worker.

Frontend replicas were subsequently observed on that same hostname topology domain.

This demonstrates service co-location based on workload labels rather than fixed node names.

Typical use cases include:

- latency-sensitive service relationships
- cache and application co-location
- processing services near supporting components
- topology-aware workload grouping

## Required Pod Anti-Affinity

The cache workload uses:

    requiredDuringSchedulingIgnoredDuringExecution

with:

    app=cache

and:

    topologyKey=kubernetes.io/hostname

This creates a hard rule preventing two cache replicas from occupying the same hostname topology domain.

With three eligible nodes and three replicas, the scheduler produced:

    3 Ready replicas
    3 distinct nodes
    1 cache replica per hostname

## Tolerations for Topology Availability

Two nodes already had scheduling taints:

    control-plane:
    node-role.kubernetes.io/control-plane=:NoSchedule

    database worker:
    dedicated=database:NoSchedule

Without matching tolerations, only the second worker was eligible for the cache workload.

The cache specification therefore includes tolerations for both taints.

This allowed all three nodes to participate as valid topology domains while keeping the hard pod anti-affinity rule unchanged.

## Topology Exhaustion

The cache deployment was scaled from:

    3 replicas

to:

    4 replicas

while retaining required hostname anti-affinity.

Because the cluster contains only three hostname topology domains, the fourth replica could not be scheduled.

The scheduler explicitly reported:

    0/3 nodes are available
    nodes did not match pod anti-affinity rules

This deliberately created a valid Pending state and proved that the scheduler enforced the hard anti-affinity constraint.

The deployment was then returned to three replicas.

## Anti-Affinity-Aware Rolling Updates

An additional scheduler interaction appeared when the cache Pod template was updated.

The default Deployment RollingUpdate behavior permits a temporary surge replica.

For a workload that already has one hard anti-affinity replica on every available hostname, a surge replica has no valid topology domain.

The rollout strategy was therefore changed to:

    type: RollingUpdate
    maxSurge: 0
    maxUnavailable: 1

This allows Kubernetes to terminate one existing replica before creating its replacement.

The deployment then converged successfully to:

    3 updated replicas
    3 Ready replicas
    3 distinct hostname domains
    0 unexpected Pending replicas

This demonstrates the interaction between scheduler constraints and Deployment rollout strategy.

## Combined Scheduling Policy

The `complex-app` workload combines several scheduling mechanisms simultaneously.

### Toleration

    dedicated=database:NoSchedule

### Preferred Node Affinity

    tier=database
    weight=80

### Preferred Pod Affinity

    app=database-tolerant
    weight=60
    topology=kubernetes.io/hostname

### Preferred Pod Anti-Affinity

    app=complex
    weight=40
    topology=kubernetes.io/hostname

The workload became fully Ready while the scheduler evaluated these competing preferences together.

This illustrates how real Kubernetes scheduling decisions can depend on several independent scoring and eligibility mechanisms.

## Scheduler Decision Model

The scenarios demonstrate two broad stages of Kubernetes scheduling.

### Filtering

Hard requirements eliminate nodes that are not eligible.

Examples:

    required node affinity
    untolerated NoSchedule taints
    required pod anti-affinity

A node that fails one of these constraints cannot host the Pod.

### Scoring

Preferred rules influence ranking between nodes that survived filtering.

Examples:

    preferred node affinity
    preferred pod affinity
    preferred pod anti-affinity

The scheduler can select another eligible node if the preferred location is unavailable.

## Deliberate Pending States

Pending Pods were treated as diagnostic evidence rather than automatically as failures.

Two intentional scenarios were validated.

### Untolerated Taint

A Pod targeted the tainted database worker without the matching toleration.

Result:

    Pending

Cause:

    untolerated NoSchedule taint

### Anti-Affinity Topology Exhaustion

A fourth cache replica was requested across only three hostname domains.

Result:

    Pending

Cause:

    every hostname already contained a conflicting cache replica

These scenarios demonstrate scheduler troubleshooting through events and Pod descriptions.

## Monitoring

A reusable monitoring script captures:

- node labels
- node taints
- Pod placement
- Pending workloads
- deployment state
- recent scheduler events

Run:

    ./scripts/monitor-scheduling.sh

This provides a compact operational view of scheduling policy behavior.

## Validation Matrix

    Required node affinity
    PASS

    Preferred node affinity
    PASS

    Preferred-node fallback
    PASS

    NoSchedule taint
    PASS

    Workload without toleration
    PASS - intentionally Pending

    Matching toleration
    PASS

    Preferred pod affinity
    PASS

    Required pod anti-affinity
    PASS

    Three-way hostname spread
    PASS

    Anti-affinity topology exhaustion
    PASS

    Anti-affinity-aware rolling update
    PASS

    Combined scheduling policy
    PASS

    Scheduler event analysis
    PASS

    Monitoring
    PASS

## Final Workload State

    database-app
    2/2 Ready

    web-app
    3/3 Ready

    database-tolerant
    2/2 Ready

    frontend-app
    2/2 Ready

    cache-app
    3/3 Ready across 3 distinct nodes

    complex-app
    2/2 Ready

    no-toleration-test
    Pending by design

## Repository Structure

    kubernetes-scheduling-policies/
    |
    +-- README.md
    |
    +-- manifests/
    |   +-- kind-cluster.yaml
    |   +-- database-deployment.yaml
    |   +-- web-deployment.yaml
    |   +-- no-toleration-pod.yaml
    |   +-- frontend-with-affinity.yaml
    |   +-- cache-with-anti-affinity.yaml
    |   +-- complex-scheduling.yaml
    |
    +-- scripts/
    |   +-- monitor-scheduling.sh
    |
    +-- evidence/
        +-- final-scheduling-validation.txt
        +-- final-architecture.txt
        +-- final-node-labels.txt
        +-- final-node-taints.txt
        +-- final-pod-distribution.txt
        +-- final-scheduler-events.txt
        +-- final-pending-reason.txt
        +-- node-affinity-validation.txt
        +-- preferred-node-affinity-validation.txt
        +-- taint-toleration-validation.txt
        +-- pod-affinity-validation.txt
        +-- combined-scheduling-validation.txt
        +-- cache-topology-exhaustion-proof.txt
        +-- cache-rollout-strategy-recovery.txt
        +-- cache-final-recovered-placement.txt

## Skills Demonstrated

This implementation demonstrates practical experience with:

- Kubernetes scheduling architecture
- kind multi-node clusters
- node labels
- required node affinity
- preferred node affinity
- taints
- tolerations
- pod affinity
- pod anti-affinity
- topology keys
- scheduler filtering
- scheduler scoring
- controlled Pending states
- scheduler event analysis
- Deployment rollout strategy
- resource-aware placement
- Kubernetes troubleshooting
- operational monitoring
- declarative YAML configuration

## Operational Relevance

These scheduling mechanisms are commonly used to:

- isolate specialized workloads
- reserve nodes for particular workload classes
- place workloads near dependent services
- distribute replicas for resilience
- enforce one-replica-per-host patterns
- support infrastructure maintenance
- control expensive or specialized compute placement
- prevent concentration of critical replicas
- coordinate rollout behavior with topology restrictions

Production environments can extend the same concepts across:

    kubernetes.io/hostname
    topology.kubernetes.io/zone
    topology.kubernetes.io/region

depending on the infrastructure failure domains available.

## Scope

The Kubernetes cluster runs as kind nodes on a single underlying host.

The implementation therefore validates Kubernetes scheduler behavior across independent Kubernetes node objects and containerized nodes.

It does not represent independent physical-host, availability-zone, or datacenter fault isolation.

The scheduling semantics, constraints, events, affinity evaluation, taint handling, and topology behavior remain directly observable within the cluster.

## Final Outcome

The completed environment validates a broad set of Kubernetes scheduling mechanisms from simple node selection through multi-policy scheduler decisions.

The strongest operational outcomes were:

- deterministic database placement through required node affinity
- flexible web placement through preferred affinity
- dedicated-node isolation through NoSchedule taints
- explicit scheduling permission through tolerations
- workload co-location through pod affinity
- replica separation through required pod anti-affinity
- deliberate topology exhaustion and scheduler diagnostics
- rollout strategy adaptation for hard anti-affinity workloads
- combined affinity and toleration policies
- repeatable monitoring and evidence capture

Final result:

    SUCCESS
