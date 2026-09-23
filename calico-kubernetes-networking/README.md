# Calico Kubernetes Networking

## What This Does

This implementation builds and validates a multi-node Kubernetes networking environment using Calico as the Container Network Interface.

The Kubernetes cluster consists of one control-plane node and two worker nodes. The default kind CNI is disabled so Calico is responsible for Pod networking, IP address management, routing, and NetworkPolicy enforcement.

The implementation covers:

- Calico installation and CNI configuration
- multi-node Kubernetes networking
- Pod IP allocation from a dedicated Calico pool
- bidirectional cross-node Pod connectivity
- network routing and CNI inspection
- deliberate Calico component failure
- DaemonSet self-healing validation
- reusable network diagnostics and recovery
- three-tier application segmentation
- default-deny NetworkPolicies
- allowed and blocked traffic validation
- cross-node throughput measurement with iperf3

## Architecture

```text
                    Kubernetes Cluster
                           |
          +----------------+----------------+
          |                                 |
          v                                 v
    Control Plane                     Worker Nodes
                                           |
                              +------------+------------+
                              |                         |
                              v                         v
                        Worker Node 1             Worker Node 2
                              |                         |
                              +------------+------------+
                                           |
                                           v
                                      Calico CNI
                                           |
                   +-----------------------+-----------------------+
                   |                       |                       |
                   v                       v                       v
             Pod Networking         NetworkPolicy             Diagnostics
                   |                       |                       |
                   v                       v                       v
            Cross-Node Traffic      Tier Isolation        Failure Recovery
                   |
                   v
             iperf3 Benchmark
```

## Prerequisites

- Ubuntu or compatible Linux environment
- Docker
- kubectl
- kind
- curl
- jq
- iproute2
- iptables or nftables
- sudo access
- Internet connectivity

Validated environment:

- Ubuntu 24.04 LTS
- Docker
- Kubernetes through kind
- kubectl 1.36.x
- Calico 3.32.x
- one control-plane node
- two worker nodes

## Setup & Installation

### Kubernetes Cluster

The cluster is created with the default kind CNI disabled.

```bash
kind create cluster \
  --name calico-network \
  --config kind-calico-config.yaml
```

The networking configuration uses:

```yaml
networking:
  disableDefaultCNI: true
  podSubnet: "192.168.0.0/16"
  serviceSubnet: "10.96.0.0/16"
```

Before a CNI is installed, the Kubernetes nodes are expected to remain `NotReady`.

Verify:

```bash
kubectl get nodes -o wide
```

## How to Reproduce

### 1. Install Calico

Install the Calico CRDs:

```bash
kubectl create -f calico-crds.yaml
```

Install the Tigera operator:

```bash
kubectl create -f tigera-operator.yaml
```

Apply the Calico installation configuration:

```bash
kubectl create -f calico-custom-resources.yaml
```

The configured Pod network uses:

```text
CIDR: 192.168.0.0/16
Block size: /26
Encapsulation: VXLANCrossSubnet
Outbound NAT: Enabled
```

Verify Calico:

```bash
kubectl get pods -n calico-system -o wide
kubectl get nodes -o wide
```

All nodes should transition to `Ready`.

### 2. Inspect CNI Configuration

Because kind nodes are containers, the CNI configuration exists inside each kind node rather than directly on the outer host.

List the cluster nodes:

```bash
kind get nodes --name calico-network
```

Inspect a node:

```bash
docker exec <node-name> \
  cat /etc/cni/net.d/10-calico.conflist
```

Validate the JSON:

```bash
docker exec <node-name> \
  cat /etc/cni/net.d/10-calico.conflist \
  | jq .
```

### 3. Verify Cross-Node Pod Connectivity

Two test Pods are scheduled onto different workers using stable node labels.

```text
test-pod-1
Worker Node 1
     |
     | Calico Pod Network
     |
Worker Node 2
test-pod-2
```

Deploy:

```bash
kubectl apply -f cross-node-test-pods.yaml
```

Verify placement:

```bash
kubectl get pods -n network-test -o wide
```

Run:

```bash
./test-connectivity.sh
```

The script validates both directions:

```text
test-pod-1 -> test-pod-2
test-pod-2 -> test-pod-1
```

Both Pod addresses must belong to:

```text
192.168.0.0/16
```

### 4. Inspect Routing and VXLAN State

Inspect routes on a kind node:

```bash
docker exec <node-name> ip route
```

Inspect the Calico VXLAN interface:

```bash
docker exec <node-name> \
  ip -d link show vxlan.calico
```

With `VXLANCrossSubnet`, encapsulation is topology-dependent rather than mandatory for every Pod-to-Pod packet.

### 5. Run Network Diagnostics

Execute:

```bash
./troubleshoot-network.sh
```

The script captures:

- Kubernetes node status
- Calico Pod health
- Calico DaemonSet state
- Calico controller state
- test Pod placement
- Calico IP pools
- NetworkPolicies
- node routing tables
- VXLAN interface state
- CNI configuration
- Calico logs
- CoreDNS state
- Kubernetes DNS resolution

Diagnostic snapshots are retained for before-and-after analysis.

### 6. Simulate Calico Failure

Identify Calico node agents:

```bash
kubectl get pods \
  -n calico-system \
  -l k8s-app=calico-node
```

Delete one agent:

```bash
kubectl delete pod \
  <calico-node-pod> \
  -n calico-system
```

Because the component is controlled by a DaemonSet, Kubernetes creates a replacement automatically.

Verify recovery:

```bash
kubectl rollout status \
  daemonset/calico-node \
  -n calico-system
```

Cross-node connectivity is tested again after recovery.

### 7. Execute the Recovery Procedure

Run:

```bash
./recover-network.sh
```

The procedure:

1. restarts Calico node agents
2. restarts Calico controllers
3. waits for Calico availability
4. restarts CoreDNS
5. waits for DNS recovery
6. verifies cluster node status
7. verifies cross-node Pod connectivity
8. validates Kubernetes DNS resolution

Expected recovery confirmation:

```text
Network recovery verified: connectivity restored.
```

### 8. Deploy the Three-Tier Application

The application networking model is:

```text
Frontend Namespace
        |
        | TCP/80
        v
Backend Namespace
        |
        | TCP/5432
        v
Database Namespace
```

Create the runtime database credential before deployment:

```bash
kubectl create secret generic database-credentials \
  -n database \
  --from-literal=postgres-password='REPLACE_WITH_RUNTIME_VALUE'
```

Deploy:

```bash
kubectl apply -f three-tier-app.yaml
```

The application includes:

- frontend diagnostic workload
- backend workload and ClusterIP Service
- PostgreSQL database workload and ClusterIP Service

### 9. Apply NetworkPolicies

Apply:

```bash
kubectl apply -f network-policies.yaml
```

The policy model is:

| Source | Destination | Expected |
|---|---|---|
| Frontend | Backend TCP/80 | Allowed |
| Frontend | Database TCP/5432 | Blocked |
| Backend | Database TCP/5432 | Allowed |

Run:

```bash
./test-network-policies.sh
```

Expected behavior:

```text
Frontend -> Backend: SUCCESS
Frontend -> Database: BLOCKED
Backend -> Database: SUCCESS
```

### 10. Measure Cross-Node Throughput

The iperf3 topology is:

```text
Worker Node 2                       Worker Node 1

+----------------+                 +----------------+
| iperf3-client  |  ------------>  | iperf3-server  |
+----------------+   Calico CNI    +----------------+
                              |
                              v
                     ClusterIP TCP/5201
```

Deploy:

```bash
kubectl apply -f iperf3-cross-node.yaml
```

Verify placement:

```bash
kubectl get pods \
  -n network-test \
  -o wide
```

Run:

```bash
./run-iperf3-test.sh
```

The test runs for 10 seconds and records transfer volume and bitrate.

Results are stored in:

```text
iperf3-results.txt
```

## Tools Used

- Kubernetes
- Calico
- Tigera Operator
- kind
- kubectl
- Docker
- Kubernetes NetworkPolicy
- CoreDNS
- iperf3
- netcat
- jq
- iproute2
- iptables
- nftables
- Bash

## Key Skills Demonstrated

- Kubernetes CNI architecture
- Calico installation
- Calico IP pool configuration
- Pod CIDR management
- multi-node Kubernetes networking
- cross-node Pod routing
- CNI configuration validation
- VXLAN-aware networking
- Linux network route inspection
- Kubernetes DaemonSet self-healing
- networking failure simulation
- CNI troubleshooting
- CoreDNS recovery
- reusable incident recovery automation
- Kubernetes NetworkPolicies
- namespace-based segmentation
- default-deny ingress controls
- three-tier network isolation
- allowed and denied traffic verification
- service connectivity testing
- cross-node throughput benchmarking
- iperf3 performance measurement

## Real-World Use Case

Kubernetes depends on the CNI layer for Pod addressing, routing, service communication, and traffic enforcement.

A failure at this layer can affect communication across large portions of a cluster, so platform teams need to understand both healthy and degraded network behavior.

Calico combines:

```text
Pod IP management
      +
Pod routing
      +
Network encapsulation
      +
NetworkPolicy enforcement
```

This makes it possible to provide application connectivity while simultaneously enforcing workload segmentation.

The diagnostic and recovery scripts provide a repeatable approach for responding to Kubernetes networking incidents.

## Lessons Learned

- Kubernetes nodes can remain `NotReady` until a functional Pod network is installed.
- Disabling the default kind CNI makes it possible to validate Calico as the actual cluster network.
- Pod IP addresses should be checked against the configured IP pool.
- Cross-node connectivity should be tested directly in both directions.
- CNI configuration for kind exists inside the node containers.
- Network troubleshooting requires visibility into routing, CNI configuration, Pod status, component logs, DNS, and NetworkPolicies.
- DaemonSets automatically recreate missing node-level networking agents.
- Component recreation alone is not enough; connectivity must be revalidated.
- CoreDNS should be included in Kubernetes network recovery procedures.
- NetworkPolicies should be tested with both permitted and denied connections.
- Default-deny ingress is a useful baseline for workload segmentation.
- Namespace selectors can provide clean policy boundaries between application tiers.
- `VXLANCrossSubnet` uses selective encapsulation based on network topology.
- iperf3 provides measurable evidence of cross-node network performance.
- Runtime credentials should not be stored in source-controlled Kubernetes manifests.

## Troubleshooting Log

### Missing Kubernetes Cluster

The fresh environment contained Docker and kubectl but no Kubernetes cluster.

A dedicated three-node kind cluster was created with:

```text
1 control-plane
2 workers
```

The default kind CNI was disabled.

### Missing Kernel Networking State

The initial host did not show the bridge netfilter and VXLAN modules loaded.

The required modules were loaded and Kubernetes networking sysctls were configured.

Relevant values included:

```text
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
```

### No CNI Before Calico

The cluster intentionally started without a Pod network.

The initial nodes therefore remained:

```text
NotReady
```

After Calico installation they transitioned to:

```text
Ready
```

### CNI Configuration Path

Checking `/etc/cni/net.d` directly on the outer VM does not expose the configuration used by kind nodes.

The Calico configuration was inspected inside each kind node container instead.

### Worker Scheduling

Kind-generated worker names were not assumed to match static names.

Stable labels were applied:

```text
networking-role=worker-node-1
networking-role=worker-node-2
```

Cross-node workloads use these labels for deterministic placement.

### Calico Agent Failure

A running `calico-node` Pod was deliberately deleted.

The DaemonSet created a replacement automatically.

Recovery was verified using:

```text
Calico Pod health
node readiness
cross-node connectivity
DNS resolution
```

### Reusable Network Recovery

A recovery procedure was built to restart and validate:

```text
calico-node
calico-kube-controllers
CoreDNS
```

The procedure then rechecks DNS and cross-node traffic.

### NetworkPolicy Validation

The traffic model was validated against all intended paths:

```text
Frontend -> Backend       ALLOWED
Frontend -> Database      BLOCKED
Backend  -> Database      ALLOWED
```

This confirmed that policy enforcement was active rather than merely present as configuration.

### Cross-Node Performance

The iperf3 server and client were intentionally scheduled onto different worker nodes.

A completed TCP throughput test confirmed sustained cross-node traffic through the Calico-managed Pod network.
