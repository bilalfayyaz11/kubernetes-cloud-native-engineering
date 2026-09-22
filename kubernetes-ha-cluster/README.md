# High Availability Kubernetes Control Plane

## Overview

This implementation demonstrates a highly available Kubernetes control-plane architecture with external etcd, API load balancing, TLS-secured datastore communication, controlled failure simulation, quorum validation, workload continuity, and component recovery.

The environment was built from a fresh Ubuntu host and adapted into a resource-conscious single-host HA simulation using isolated containers and logical network boundaries.

The implementation validates the operational lifecycle of a resilient Kubernetes platform:

- three Kubernetes server instances
- three-member external etcd cluster
- TLS-secured etcd client and peer communication
- HAProxy API load balancing
- Kubernetes API backend health monitoring
- replicated application deployment
- control-plane failure detection
- continued API reads during server loss
- continued API writes during server loss
- workload scaling during degraded control-plane operation
- external etcd quorum validation
- datastore writes during member loss
- failed-member recovery
- datastore synchronization after recovery
- full-platform recovery verification

## Architecture

    Client / kubectl
          |
          v
    +----------------------+
    |       HAProxy        |
    | Kubernetes API 6443  |
    +----------+-----------+
               |
        +------+------+------+
        |             |      |
        v             v      v
    +---------+  +---------+  +---------+
    | Server1 |  | Server2 |  | Server3 |
    |  API    |  |  API    |  |  API    |
    +----+----+  +----+----+  +----+----+
         |            |            |
         +------------+------------+
                      |
                      v
          +-----------------------+
          |   External etcd       |
          |                       |
          | etcd1  etcd2  etcd3  |
          | TLS + quorum          |
          +-----------------------+

## Execution Scope

The available environment contained a single Ubuntu machine instead of separate control-plane, worker, datastore, and load-balancer hosts.

The architecture was therefore implemented as a single-host, multi-container HA simulation.

Logical isolation was used for:

- Kubernetes server instances
- external etcd members
- HAProxy
- datastore storage
- network addresses
- failure domains at the process/container level

This validates control-plane redundancy, API balancing, datastore quorum, process failure handling, recovery behavior, and state consistency.

It does not represent independent machine, rack, availability-zone, or datacenter fault isolation.

## Core Components

### Kubernetes Servers

Three Kubernetes server instances provide redundant API endpoints:

    k8s-server1
    k8s-server2
    k8s-server3

Each server connects to the same external etcd cluster and participates in the same Kubernetes control plane.

All three servers were validated in the `Ready` state.

## External etcd

A three-member external etcd cluster provides the Kubernetes datastore:

    etcd1
    etcd2
    etcd3

The datastore configuration includes:

- three voting members
- leader election
- majority quorum
- TLS client communication
- TLS peer communication
- client certificate authentication
- peer certificate authentication
- replicated writes
- member recovery and resynchronization

A three-member etcd cluster can continue operating after the loss of one member because two members still form the required majority quorum.

## TLS-Secured Datastore

A dedicated certificate authority was created for the external datastore.

Each etcd member uses authenticated TLS for:

- client traffic
- peer traffic

Kubernetes servers authenticate to the datastore using a dedicated client certificate.

Private keys and authentication material are intentionally excluded from the repository.

## HAProxy API Load Balancer

HAProxy provides a stable Kubernetes API endpoint.

The load balancer distributes TCP connections across:

    k8s-server1:6443
    k8s-server2:6443
    k8s-server3:6443

The backend configuration uses:

- TCP mode
- round-robin balancing
- active TCP health checks
- automatic backend removal
- automatic backend reintegration
- dedicated operational statistics

The API frontend listens on port:

    6443

The HAProxy statistics endpoint is exposed on:

    8404

## Control-Plane Baseline

Before failure testing, the following state was verified:

    Kubernetes servers: 3/3 Ready
    HAProxy backends:   3/3 UP
    External etcd:      3/3 healthy
    etcd leader:        exactly one
    Kubernetes API:     reachable through HAProxy

This established the healthy baseline before introducing controlled failures.

## Replicated Workload

A small NGINX workload was deployed to verify application state during infrastructure failures.

Initial state:

    Deployment: ha-web
    Replicas:   3
    Service:    ClusterIP

Resource requests and limits were deliberately kept small because the full HA topology was running on a constrained host.

## Control-Plane Failure Test

The first major failure scenario simulated loss of one Kubernetes server.

The following server was stopped:

    k8s-server1

HAProxy detected that the API endpoint was unavailable and automatically removed the failed backend from rotation.

Observed load-balancer state:

    k8s-server1  DOWN
    k8s-server2  UP
    k8s-server3  UP

The Kubernetes API remained reachable through HAProxy using the surviving servers.

## API Read Continuity

During the `k8s-server1` outage, Kubernetes read operations continued successfully.

Validated operations included:

    kubectl get nodes
    kubectl get deployments
    kubectl get pods

This demonstrated that loss of one API server did not make the Kubernetes control plane unavailable.

## API Write Continuity

The platform was also tested with state-changing API requests while one control-plane server was unavailable.

The workload was scaled from:

    3 replicas

to:

    5 replicas

while `k8s-server1` remained offline.

The scaling operation succeeded and all five replicas became Ready.

A ConfigMap was also created during the outage to provide a second state-changing API validation.

Result:

    API read during failure:  PASS
    API write during failure: PASS
    Scale 3 -> 5:             PASS

## Control-Plane Recovery

After the failure validation, `k8s-server1` was restarted.

Recovery verification confirmed:

- Kubernetes API port returned
- HAProxy detected the recovered backend
- HAProxy returned the backend to rotation
- the Kubernetes node returned to `Ready`
- all three servers became healthy again
- the five-replica workload remained intact
- data written during the failure remained present

Final control-plane state:

    k8s-server1  Ready
    k8s-server2  Ready
    k8s-server3  Ready

Final load-balancer state:

    k8s-server1  UP
    k8s-server2  UP
    k8s-server3  UP

## External etcd Failure Test

A second failure scenario tested datastore resilience while Kubernetes remained active.

The following etcd member was stopped:

    etcd3

The remaining members were:

    etcd1
    etcd2

A three-member etcd cluster requires two members for quorum, so the surviving two members retained majority consensus.

## Quorum Validation

While `etcd3` was unavailable, endpoint health was verified against the surviving members.

Result:

    surviving members: 2/3
    quorum:             retained
    datastore service: operational

The Kubernetes API continued operating because the external datastore still had quorum.

## Kubernetes Operations During etcd Member Loss

With one etcd member offline, Kubernetes was tested again.

The following operations succeeded:

- Kubernetes node queries
- existing workload queries
- ConfigMap creation
- Kubernetes state persistence

This demonstrated that losing one member of the three-member external datastore did not interrupt normal control-plane operations.

## Direct Datastore Write During Failure

A direct etcd write was also performed while `etcd3` was unavailable.

The write was accepted by the surviving quorum and successfully read from another active member.

This validated replication across the surviving datastore nodes.

## etcd Member Recovery

After quorum testing, `etcd3` was restarted.

Recovery verification confirmed:

- the member became healthy
- the member rejoined the existing cluster
- writes performed during its outage appeared on the recovered member
- endpoint health returned to three healthy members
- Kubernetes remained operational throughout recovery

Final datastore state:

    etcd1  healthy
    etcd2  healthy
    etcd3  healthy

## Datastore Consistency

The implementation validated several consistency behaviors:

- cross-member reads
- replicated writes
- leader election
- write availability with one member unavailable
- recovered-member synchronization
- Kubernetes state persistence through datastore degradation

These checks demonstrate the relationship between Kubernetes availability and etcd quorum.

## Load-Balancer Failure Detection

HAProxy was validated before, during, and after control-plane failure.

Healthy baseline:

    Server1  UP
    Server2  UP
    Server3  UP

During failure:

    Server1  DOWN
    Server2  UP
    Server3  UP

After recovery:

    Server1  UP
    Server2  UP
    Server3  UP

This demonstrates automatic removal and reintegration of Kubernetes API endpoints.

## Failure Model

The implementation validates two independent failure paths.

### Kubernetes API Server Failure

    Healthy state
         |
         v
    Server1 stopped
         |
         v
    HAProxy detects failure
         |
         v
    Server1 removed
         |
         v
    Server2 + Server3 continue serving requests
         |
         v
    API reads and writes succeed
         |
         v
    Server1 restarted
         |
         v
    HAProxy detects recovery
         |
         v
    Server1 re-enters rotation

### External etcd Member Failure

    3-member healthy cluster
         |
         v
    etcd3 stopped
         |
         v
    etcd1 + etcd2 retain majority
         |
         v
    quorum remains available
         |
         v
    Kubernetes reads and writes continue
         |
         v
    etcd3 restarted
         |
         v
    member catches up
         |
         v
    3/3 datastore health restored

## Operational Verification

Final verification included:

    Kubernetes nodes
    ----------------
    3/3 Ready

    HAProxy backends
    ----------------
    3/3 UP

    External etcd
    -------------
    3/3 healthy

    etcd leader
    -----------
    exactly one

    Application
    -----------
    5/5 Ready replicas

    Control-plane failure
    ---------------------
    PASS

    API read during failure
    -----------------------
    PASS

    API write during failure
    ------------------------
    PASS

    etcd quorum during member loss
    ------------------------------
    PASS

    etcd write during member loss
    -----------------------------
    PASS

    recovery
    --------
    PASS

## Resource-Conscious Design

The complete topology was executed on a constrained host with approximately:

    CPU:    2 cores
    Memory: 3.8 GiB

Several design decisions kept resource consumption manageable:

- K3s instead of a heavier Kubernetes distribution
- disabled optional bundled components
- lightweight NGINX workload
- small resource requests
- small resource limits
- one Docker bridge network
- container-level service isolation

This allowed multiple Kubernetes servers, three etcd members, HAProxy, and application workloads to operate simultaneously.

## Security Considerations

Sensitive runtime material is not intended for source control.

Excluded material includes:

- cluster token
- kubeconfig
- etcd CA private key
- etcd member private keys
- datastore client private key
- runtime data directories
- Kubernetes state databases
- generated certificates containing private material

Only recruiter-safe configuration, manifests, and validation evidence are packaged.

## Repository Structure

    kubernetes-ha-cluster/
    |
    +-- README.md
    |
    +-- config/
    |   +-- haproxy/
    |       +-- haproxy.cfg
    |
    +-- manifests/
    |   +-- ha-web-deployment.yaml
    |   +-- ha-web-service.yaml
    |
    +-- evidence/
        +-- topology-scope.txt
        +-- environment-baseline.txt
        +-- etcd-member-list.txt
        +-- etcd-endpoint-health.txt
        +-- etcd-endpoint-status.txt
        +-- etcd-one-member-failure.txt
        +-- etcd-final-health.txt
        +-- etcd-final-status.txt
        +-- etcd-ha-summary.txt
        +-- haproxy-architecture.txt
        +-- three-server-node-status.txt
        +-- haproxy-three-server-status.csv
        +-- three-server-control-plane-summary.txt
        +-- ha-web-before-control-plane-failure.txt
        +-- nodes-during-server1-failure.txt
        +-- ha-web-during-control-plane-failure.txt
        +-- haproxy-server1-failure.csv
        +-- control-plane-failover-summary.txt
        +-- etcd-pre-failure-health.txt
        +-- etcd-pre-failure-status.txt
        +-- etcd-health-during-member-failure.txt
        +-- nodes-during-etcd-member-failure.txt
        +-- workload-during-etcd-member-failure.txt
        +-- etcd-member-failure-validation.txt
        +-- etcd-post-recovery-health.txt
        +-- etcd-post-recovery-status.txt
        +-- etcd-failover-summary.txt
        +-- final-kubernetes-nodes.txt
        +-- final-haproxy-status.csv
        +-- final-load-balanced-api-version.json
        +-- final-etcd-health.txt
        +-- final-etcd-members.txt
        +-- final-etcd-status.txt
        +-- final-system-pods.txt
        +-- final-ha-workload.txt
        +-- final-ha-workload-pods.txt
        +-- final-resource-usage.txt
        +-- final-architecture.txt
        +-- final-ha-validation-summary.txt

## Skills Demonstrated

This implementation demonstrates practical experience with:

- Kubernetes control-plane architecture
- high-availability design
- external etcd
- etcd quorum
- etcd leader election
- etcd TLS
- certificate-based authentication
- HAProxy
- TCP load balancing
- backend health checking
- Kubernetes API redundancy
- failure simulation
- degraded-state operations
- recovery testing
- state consistency
- Docker networking
- Linux troubleshooting
- resource-constrained infrastructure
- operational evidence collection

## Operational Relevance

The same core concepts apply to production Kubernetes architecture:

- multiple control-plane nodes
- stable API endpoints
- external or distributed datastores
- odd-numbered etcd membership
- quorum-aware failure handling
- health-based backend selection
- recovery validation
- workload continuity testing
- infrastructure observability
- controlled failure exercises

A real production implementation would distribute these components across independent machines and preferably independent failure domains.

## Final Outcome

The completed environment successfully demonstrated:

    Kubernetes servers:          3/3 Ready
    HAProxy API backends:        3/3 UP
    External etcd members:       3/3 healthy
    TLS datastore security:      enabled
    etcd leader election:        validated
    control-plane failover:      validated
    API read continuity:         validated
    API write continuity:        validated
    workload scaling in failure: validated
    etcd member failover:        validated
    quorum writes:               validated
    datastore recovery:          validated
    data synchronization:        validated
    final workload:              5/5 Ready

The implementation provides a practical demonstration of Kubernetes control-plane resilience, load-balanced API access, external datastore quorum, controlled failure handling, and recovery operations.
