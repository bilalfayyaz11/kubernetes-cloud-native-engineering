# Kubernetes Advanced Troubleshooting

## What This Does

This implementation demonstrates systematic diagnosis and recovery of critical Kubernetes control-plane and networking failures.

It covers four production-relevant incident scenarios:

- etcd outage and point-in-time disaster recovery
- kube-apiserver static Pod misconfiguration
- Kubernetes Service target-port failure
- Pod-level cluster DNS misconfiguration

The workflow intentionally introduces faults, captures failure evidence, isolates root causes, performs controlled recovery, and validates platform health afterward.

The emphasis is not simply on restoring service. Each scenario records the observable symptoms, diagnostic path, recovery actions, and evidence proving that the identified root cause was actually resolved.

## Architecture

```text
                         Kubernetes Cluster
                                |
              +-----------------+-----------------+
              |                                   |
              v                                   v
       Control Plane                        Workload Network
              |                                   |
     +--------+--------+                  +-------+-------+
     |                 |                  |               |
     v                 v                  v               v
   etcd          kube-apiserver        Service          DNS
     |                 |                  |               |
     |                 |                  |               |
 snapshot          static Pod         EndpointSlice    CoreDNS
 recovery          configuration       targetPort       resolver
     |                 |                  |               |
     +--------+--------+                  +-------+-------+
              |                                   |
              v                                   v
        Cluster State                        Applications
              |
              v
       Validation Evidence
```

## Prerequisites

- Ubuntu 24.04 LTS or compatible Linux system
- sudo privileges
- containerd
- kubeadm
- kubelet
- kubectl
- crictl
- etcdctl
- etcdutl
- tcpdump
- traceroute
- dig
- nslookup
- jq
- curl
- a functioning Kubernetes CNI

Validated environment:

```text
Ubuntu 24.04.3 LTS
Kubernetes 1.36.x
containerd
Flannel CNI
single-node kubeadm control plane
stacked etcd
```

## Setup & Installation

The environment was initialized as a fresh single-node Kubernetes control plane.

Core preparation included:

- disabling swap
- loading `overlay` and `br_netfilter`
- enabling IPv4 forwarding
- configuring containerd to use systemd cgroups
- installing kubeadm, kubelet, crictl, and troubleshooting utilities
- initializing the control plane with kubeadm
- installing Flannel
- enabling workload scheduling on the control-plane node
- installing `etcdctl` and `etcdutl` matching the etcd version used by Kubernetes

Example cluster initialization:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<CONTROL_PLANE_IP> \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock
```

The Kubernetes client configuration was then installed under:

```text
$HOME/.kube/config
```

## How to Reproduce

### 1. Establish a Healthy Control-Plane Baseline

Validate node and control-plane health:

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
kubectl get --raw='/readyz'
```

Verify etcd directly:

```bash
sudo etcdctl \
  --endpoints=<ETCD_ENDPOINT> \
  --cacert=<CA_CERT> \
  --cert=<CLIENT_CERT> \
  --key=<CLIENT_KEY> \
  endpoint health
```

The etcd connection parameters should be derived from the live static Pod manifest rather than hard-coded.

Relevant settings include:

```text
--name
--data-dir
--advertise-client-urls
--initial-advertise-peer-urls
--initial-cluster
--trusted-ca-file
--cert-file
--key-file
```

## etcd Disaster Recovery

### Recovery State

A namespace containing a Deployment, Service, and recovery marker ConfigMap is created before the snapshot.

The object UIDs are recorded so a later restore can prove that the original Kubernetes objects returned rather than being recreated manually.

Example recovery state:

```text
Namespace
Deployment
Service
ConfigMap
```

### Snapshot Creation

The live snapshot is created with `etcdctl`:

```bash
sudo etcdctl \
  --endpoints=<ETCD_ENDPOINT> \
  --cacert=<CA_CERT> \
  --cert=<CLIENT_CERT> \
  --key=<CLIENT_KEY> \
  snapshot save /opt/etcd-backup/etcd-snapshot.db
```

Offline snapshot verification uses `etcdutl`:

```bash
sudo etcdutl \
  --write-out=table \
  snapshot status /opt/etcd-backup/etcd-snapshot.db
```

A SHA-256 checksum is also generated and verified before performing any destructive action.

### Point-in-Time Recovery Proof

After the snapshot, another ConfigMap is created.

Expected state before failure:

```text
pre-snapshot recovery-marker     -> PRESENT
post-snapshot-marker             -> PRESENT
```

Expected state after restoring the earlier snapshot:

```text
pre-snapshot recovery-marker     -> PRESENT
post-snapshot-marker             -> ABSENT
```

This provides concrete proof that Kubernetes returned to the snapshot point rather than merely restarting etcd.

### Failure Simulation

The kubelet is temporarily stopped to prevent immediate static Pod recreation.

The running etcd container is then stopped through CRI:

```bash
sudo crictl stop <ETCD_CONTAINER_ID>
```

Failure evidence includes:

- etcd endpoint health failure
- API server readiness degradation
- failed Kubernetes API operations
- CRI container state
- kube-apiserver logs
- control-plane socket state

### Safe Restore

The failed datastore is preserved:

```text
/var/lib/etcd-failed-<timestamp>
```

The verified snapshot is restored into a new active data directory using `etcdutl`.

The recovery uses:

```text
--bump-revision
--mark-compacted
```

This avoids restoring Kubernetes into an older visible etcd revision that could leave controllers with stale informer state.

Conceptually:

```bash
sudo etcdutl snapshot restore <SNAPSHOT> \
  --data-dir=<ETCD_DATA_DIR> \
  --name=<ETCD_MEMBER> \
  --initial-cluster=<INITIAL_CLUSTER> \
  --initial-advertise-peer-urls=<PEER_URL> \
  --bump-revision=1000000000 \
  --mark-compacted
```

After the restore, kubelet is restarted and the platform is validated.

### Recovery Validation

Recovery is considered successful only when all of the following are true:

```text
etcd endpoint health       -> healthy
kube-apiserver /readyz     -> ready
node                       -> Ready
original object UIDs       -> unchanged
pre-snapshot marker        -> restored
post-snapshot marker       -> absent
new Kubernetes write       -> succeeds
application Service        -> reachable
```

## kube-apiserver Troubleshooting

The kube-apiserver runs as a static Pod controlled by kubelet.

Its manifest is stored at:

```text
/etc/kubernetes/manifests/kube-apiserver.yaml
```

A critical operational rule is that ordinary backup files should not be placed inside the static Pod manifest directory.

Known-good backups are therefore stored separately.

### Incident 1: Invalid Secure Port

The valid configuration:

```text
--secure-port=6443
```

is deliberately changed to:

```text
--secure-port=invalid-port
```

Expected symptoms include:

- API operations fail
- port 6443 disappears
- kube-apiserver container exits or restarts
- CRI reports failed container state
- kubelet reports static Pod restart failures
- kube-apiserver logs expose argument parsing errors

### Diagnostic Workflow

Runtime state:

```bash
sudo crictl ps -a --name kube-apiserver
```

Container logs:

```bash
sudo crictl logs <CONTAINER_ID>
```

Kubelet diagnostics:

```bash
sudo journalctl \
  -u kubelet \
  --since "5 minutes ago" \
  --no-pager
```

Socket inspection:

```bash
sudo ss -lntp | grep ':6443'
```

Manifest inspection:

```bash
sudo grep -- '--secure-port=' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

Recovery restores the known-good manifest and waits for `/readyz`.

## TLS Certificate Path Failure

The second API-server incident deliberately replaces the valid certificate path with a nonexistent path.

Example failure:

```text
--tls-cert-file=/etc/kubernetes/pki/nonexistent-apiserver.crt
```

Expected symptoms:

```text
API unavailable
kube-apiserver startup failure
TLS/certificate error in logs
kubelet restart attempts
```

The diagnosis again correlates:

- manifest configuration
- CRI state
- kube-apiserver logs
- kubelet logs
- socket state
- readiness endpoint

Recovery restores the original certificate configuration.

## Kubernetes Service Networking Failure

A two-replica nginx workload is exposed through a ClusterIP Service.

The intentional misconfiguration is:

```yaml
ports:
  - port: 80
    targetPort: 8080
```

while nginx listens on:

```text
TCP/80
```

### Initial Symptoms

The following may all appear healthy:

```text
web Pods       -> Ready
client Pod     -> Ready
Service        -> exists
DNS            -> resolves
selector       -> matches
EndpointSlice  -> populated
```

but HTTP requests through the Service fail.

This demonstrates that the existence of valid endpoints does not guarantee that the target application port is correct.

### Diagnostic Isolation

Direct Pod access:

```bash
curl http://<POD_IP>:80
```

Expected:

```text
SUCCESS
```

Direct access to the incorrect backend port:

```bash
curl http://<POD_IP>:8080
```

Expected:

```text
FAILURE
```

Service DNS:

```bash
nslookup web-service.network-debug.svc.cluster.local
```

Expected:

```text
SUCCESS
```

Service HTTP request:

```bash
curl http://web-service.network-debug.svc.cluster.local
```

Expected before correction:

```text
FAILURE
```

The comparison isolates the fault to Service port forwarding rather than DNS, Pod readiness, or CNI connectivity.

## EndpointSlice Analysis

EndpointSlices are inspected with:

```bash
kubectl get endpointslices \
  -n network-debug \
  -l kubernetes.io/service-name=web-service
```

They confirm both:

- the backend Pod addresses
- the port selected by the Service

Before the fix:

```text
EndpointSlice port: 8080
```

After the fix:

```text
EndpointSlice port: 80
```

## Packet Capture

Traffic is captured from the Kubernetes node using `tcpdump`.

Example:

```bash
sudo tcpdump \
  -i any \
  -nn \
  host <WEB_POD_IP> \
  -w service-failure-traffic.pcap
```

Traffic is then generated from the client Pod and decoded:

```bash
sudo tcpdump \
  -nn \
  -r service-failure-traffic.pcap
```

The capture provides packet-level evidence supporting the Service configuration diagnosis.

## Route Analysis

The troubleshooting process also captures:

```bash
traceroute <POD_IP>
traceroute <SERVICE_IP>
ip route
```

These results help distinguish routing problems from application-port problems.

## Service Recovery

The root cause is corrected by changing:

```text
targetPort: 8080
```

to:

```text
targetPort: 80
```

After the correction:

```text
direct Pod request      -> SUCCESS
ClusterIP request       -> SUCCESS
Service DNS request     -> SUCCESS
nginx response          -> VERIFIED
```

## Kubernetes DNS Failure

The final incident isolates Pod-level DNS configuration.

An intentionally broken Pod uses:

```yaml
dnsPolicy: None
dnsConfig:
  nameservers:
    - 192.0.2.53
```

The reserved address provides an intentionally unusable resolver while keeping the Pod specification valid.

## DNS Isolation Tests

With the broken resolver:

```text
direct Pod IP request      -> SUCCESS
Service ClusterIP request  -> SUCCESS
Service DNS lookup         -> FAILURE
kubernetes.default lookup  -> FAILURE
```

This is strong evidence that general Pod networking remains functional while name resolution is broken.

The Pod resolver configuration is inspected through:

```bash
cat /etc/resolv.conf
```

Its configured nameserver is compared with the `kube-dns` ClusterIP.

## CoreDNS Isolation

CoreDNS health is separately verified:

```bash
kubectl get pods \
  -n kube-system \
  -l k8s-app=kube-dns

kubectl get service kube-dns \
  -n kube-system
```

The broken Pod then explicitly queries the real CoreDNS Service:

```bash
nslookup \
  web-service.network-debug.svc.cluster.local \
  <COREDNS_SERVICE_IP>
```

Expected:

```text
SUCCESS
```

This proves CoreDNS itself is functional and isolates the failure to the Pod resolver configuration.

## DNS Recovery

The Pod is deleted and recreated with:

```yaml
dnsPolicy: ClusterFirst
```

Recreation is used instead of trying to mutate the immutable networking-related Pod configuration in place.

After recovery:

```text
Service FQDN              -> resolves
kubernetes.default FQDN   -> resolves
short Service name        -> resolves
HTTP via Service DNS      -> succeeds
ClusterIP connectivity    -> succeeds
```

## Failure Isolation Matrix

```text
+----------------------+----------------------+--------------------------+
| Scenario             | Root Cause           | Primary Evidence         |
+----------------------+----------------------+--------------------------+
| etcd outage          | datastore offline    | etcdctl + /readyz        |
| API port failure     | invalid secure-port  | crictl + kubelet logs    |
| API TLS failure      | bad certificate path | apiserver logs           |
| Service failure      | targetPort mismatch  | EndpointSlice + tcpdump  |
| DNS failure          | bad Pod resolver     | resolv.conf + DNS tests  |
+----------------------+----------------------+--------------------------+
```

## Tools Used

- Kubernetes
- kubeadm
- kubelet
- kubectl
- containerd
- crictl
- etcd
- etcdctl
- etcdutl
- Flannel
- CoreDNS
- EndpointSlice
- tcpdump
- traceroute
- dig
- nslookup
- curl
- jq
- journalctl
- ss
- iproute2
- Bash

## Key Skills Demonstrated

- Kubernetes control-plane troubleshooting
- etcd disaster recovery
- point-in-time cluster recovery
- snapshot validation
- checksum verification
- etcd revision management
- static Pod debugging
- kube-apiserver recovery
- CRI-level diagnostics
- kubelet log analysis
- certificate-path troubleshooting
- socket-level diagnostics
- Kubernetes Service troubleshooting
- EndpointSlice inspection
- targetPort diagnosis
- packet capture analysis
- route analysis
- Kubernetes DNS troubleshooting
- CoreDNS isolation
- resolver inspection
- failure-domain isolation
- post-recovery validation
- evidence-driven incident response

## Real-World Use Case

A production Kubernetes outage can present as a broad cluster failure even when the root cause exists in only one subsystem.

A useful troubleshooting model is:

```text
User reports outage
        |
        v
Is API reachable?
        |
        +--> No
        |     |
        |     +--> Check kube-apiserver
        |     +--> Check etcd
        |
        +--> Yes
              |
              v
        Are workloads healthy?
              |
              +--> No
              |     |
              |     +--> controller events
              |     +--> runtime state
              |
              +--> Yes
                    |
                    v
             Is Service reachable?
                    |
                    +--> No
                    |     |
                    |     +--> selector
                    |     +--> EndpointSlice
                    |     +--> targetPort
                    |     +--> packet capture
                    |
                    +--> Yes
                          |
                          v
                    Does DNS resolve?
                          |
                          +--> No
                                |
                                +--> resolv.conf
                                +--> kube-dns Service
                                +--> CoreDNS
```

This prevents random configuration changes and encourages evidence-driven fault isolation.

## Lessons Learned

- etcd is the authoritative backing store for Kubernetes cluster state.
- A restart is not equivalent to disaster recovery.
- Snapshot integrity should be verified before relying on a recovery point.
- Checksums provide an additional integrity check for backup artifacts.
- Point-in-time recovery can be proven by creating data after the snapshot and confirming that it disappears after restore.
- Kubernetes object UIDs provide strong evidence that original state was restored.
- A failed etcd datastore should be preserved rather than immediately destroyed.
- Modern etcd recovery uses `etcdutl` for offline restore operations.
- Revision bumping is important when restoring Kubernetes from older etcd state.
- Static Pod configuration errors can make the Kubernetes API completely unavailable.
- `crictl` remains useful when `kubectl` cannot function.
- kubelet logs are critical when control-plane static Pods fail.
- Static Pod backups should be stored outside `/etc/kubernetes/manifests`.
- A healthy Service selector does not guarantee correct backend connectivity.
- EndpointSlices can expose the backend addresses and effective target port.
- Direct Pod-IP tests help separate application health from Service forwarding.
- Packet capture can confirm how traffic is being forwarded at the node level.
- DNS failures should be separated from general network failures.
- Successful raw IP connectivity with failed name resolution strongly points toward DNS.
- Querying CoreDNS explicitly can distinguish CoreDNS failure from Pod resolver failure.
- Kubernetes Pods should generally use `ClusterFirst` DNS unless a custom resolver is intentionally required.
- Recovery is incomplete until the platform accepts new writes and end-to-end application traffic succeeds.
- Troubleshooting should follow evidence from one layer to the next rather than applying speculative changes.

## Troubleshooting Log

### Fresh Environment Had No Cluster

The starting host contained containerd and kubectl but no kubeadm control plane, kubelet, CRI tooling, CNI configuration, or etcd utilities.

A fresh Kubernetes control plane was built before the incident scenarios were introduced.

### etcd Tools Were Matched to the Running Server

The running etcd image version was discovered from the static Pod.

Matching `etcdctl` and `etcdutl` binaries were installed rather than assuming the operating system package version would be compatible.

### Hard-Coded etcd Restore Parameters Were Avoided

The restore process derived member name, peer URL, initial cluster configuration, data directory, and TLS paths directly from the live etcd manifest.

This reduced assumptions about the cluster configuration.

### etcd Was Intentionally Prevented from Restarting

Stopping only the etcd container would allow kubelet to recreate the static Pod.

kubelet was therefore stopped before the etcd container to create a controlled datastore outage.

### Old Datastore Was Preserved

The failed datastore was renamed rather than deleted.

This created a rollback path and retained incident evidence.

### Restore Used Revision Protection

The snapshot was restored using a large revision bump and `mark-compacted` behavior.

This prevents restored Kubernetes state from appearing older than revisions already observed by cluster controllers.

### API Server Backups Were Stored Safely

The known-good kube-apiserver manifests were kept outside:

```text
/etc/kubernetes/manifests
```

This avoids kubelet interpreting backup files as additional static Pod definitions.

### `journalctl -f` Was Avoided

A bounded journal query was used rather than following logs indefinitely.

This produces reproducible diagnostic evidence and avoids leaving troubleshooting sessions attached to a live stream.

### Service Had Healthy Backends but Failed Traffic

The web Pods were Ready and EndpointSlices contained backend addresses.

The failure was the Service forwarding to TCP/8080 while nginx listened on TCP/80.

### Packet Capture Confirmed the Networking Investigation

A `.pcap` file was captured during the failed Service request and decoded for review.

This provided network-level evidence alongside Kubernetes object inspection.

### DNS Failure Was Deliberately Isolated

The broken DNS Pod used an invalid resolver while raw Pod-IP and Service-IP connectivity remained functional.

Direct CoreDNS queries still succeeded.

This isolated the incident to the Pod's resolver configuration.

### DNS Pod Was Recreated Instead of Patched

The correct recovery removed the broken Pod and recreated it using `ClusterFirst`.

This restored normal Kubernetes service discovery.

### Final Cross-System Validation

Before cleanup, the following were validated together:

```text
etcd                     healthy
kube-apiserver            ready
node                      Ready
CoreDNS                   healthy
recovered application     reachable
Service targetPort        corrected
EndpointSlice             correct
Service DNS               resolving
HTTP through Service      successful
```

Runtime test namespaces were removed only after the evidence had been preserved.
