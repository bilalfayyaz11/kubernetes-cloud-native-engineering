# Kubernetes Cluster Bootstrap and Disaster Recovery

## Overview

This implementation demonstrates Kubernetes cluster administration using kubeadm, containerd, Flannel, and etcd disaster-recovery procedures.

The environment was initialized from a fresh Ubuntu host and configured into a functioning Kubernetes control plane with:

- kubeadm cluster initialization
- containerd CRI integration
- systemd cgroup configuration
- Flannel pod networking
- Kubernetes node and pod CIDR validation
- worker join credential generation and verification
- workload scheduling validation
- etcd health inspection
- live etcd snapshot backup
- simulated Kubernetes state loss
- etcd snapshot restoration
- restored application state verification
- post-recovery API, networking, and service validation

The source environment expected a three-node topology with one control plane and two worker nodes. The actual runtime environment exposed only one independent machine, so worker-node join procedures were validated without falsely claiming multi-node membership.

---

## Architecture

~~text
                    Kubernetes Control Plane
                             |
            +----------------+----------------+
            |                |                |
            v                v                v
      kube-apiserver    kube-scheduler   controller-manager
            |
            v
           etcd
            |
            v
        Cluster State

            |
            v
        containerd
            |
            v
         kubelet
            |
            v
      Flannel CNI
            |
            v
       Workload Pods
~~

Worker-node bootstrap flow:

~~text
Independent Worker Host
        |
        v
containerd + kubelet + kubeadm
        |
        v
kubeadm join
        |
        v
API server trust bootstrap
        |
        v
Node registration
~~

The actual environment contained no separate worker machines, so the worker join process was generated and validated but not executed against nonexistent nodes.

---

## Environment

The implementation used:

- Ubuntu 24.04
- Kubernetes v1.36
- kubeadm
- kubelet
- kubectl
- containerd 2.x
- crictl
- Flannel CNI
- etcdctl
- etcdutl

The environment was treated as fresh and validated before configuration.

---

## Container Runtime Preparation

containerd was explicitly configured before kubeadm initialization.

Key runtime requirements included:

- CRI enabled
- `SystemdCgroup = true`
- `/run/containerd/containerd.sock`
- required kernel modules
- IPv4 forwarding
- bridge netfilter
- swap disabled

The CRI endpoint was validated before running kubeadm:

~~bash
sudo crictl info
~~

This prevents kubeadm from starting against an invalid or unavailable CRI v1 endpoint.

---

## Kernel and Networking Prerequisites

Required modules:

~~text
overlay
br_netfilter
~~

Required sysctl configuration:

~~text
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
~~

Swap was disabled to satisfy Kubernetes node requirements.

---

## Kubernetes Control Plane Bootstrap

The control plane was initialized with kubeadm using:

~~text
Pod CIDR: 10.244.0.0/16
CRI socket: unix:///run/containerd/containerd.sock
~~

The API server advertised the host's primary private IP.

After initialization:

- `/etc/kubernetes/admin.conf` was copied into the user kubeconfig
- cluster access was verified
- control-plane static Pods were inspected
- etcd static Pod presence was confirmed
- Kubernetes API port 6443 was validated

---

## Flannel Pod Networking

Flannel was installed as the cluster CNI.

Validation included:

- Flannel DaemonSet readiness
- Flannel Pod status
- control-plane node readiness
- assigned Pod CIDR
- CoreDNS readiness
- workload scheduling

The node was made schedulable because the environment contained no worker nodes.

This is a single-host adaptation only; in a normal multi-node cluster the control-plane taint would typically remain in place.

---

## Worker Join Workflow

A short-lived kubeadm join command was generated using:

~~bash
sudo kubeadm token create --ttl 2h --print-join-command
~~

The live join command was stored locally only and was not included in repository artifacts.

Worker join validation checked:

- API endpoint
- bootstrap token format
- active bootstrap token
- cluster CA discovery hash
- API port 6443 availability
- expected CRI socket
- control-plane endpoint consistency

The worker discovery hash was independently calculated from the Kubernetes cluster CA and compared with the generated join command.

No worker-node membership is claimed because the environment did not provide separate worker hosts.

---

## Node and Scheduling Validation

The Kubernetes node was inspected for:

- control-plane role label
- taints
- Pod CIDR
- readiness condition
- assigned workload Pods

A three-replica nginx Deployment was created to verify scheduling.

Because only one node existed, all replicas were expected to schedule onto that node.

The evidence records the number of distinct scheduling nodes instead of presenting single-node placement as multi-node distribution.

---

## etcd Architecture

kubeadm deployed etcd as a static Pod.

The implementation verified:

- etcd static Pod manifest
- `/var/lib/etcd`
- etcd member list
- endpoint health
- endpoint status
- TLS-based local access

etcd client connections used:

~~text
Endpoint:
https://127.0.0.1:2379

CA:
/etc/kubernetes/pki/etcd/ca.crt

Client certificate:
/etc/kubernetes/pki/etcd/healthcheck-client.crt

Client key:
/etc/kubernetes/pki/etcd/healthcheck-client.key
~~

---

## etcd Tooling

The etcd release used by the kubeadm static Pod was detected from the manifest.

Matching versions of:

~~text
etcdctl
etcdutl
~~

were installed.

The responsibilities were intentionally separated:

~~text
etcdctl
  -> live etcd cluster interaction
  -> endpoint health
  -> member inspection
  -> snapshot creation

etcdutl
  -> offline snapshot inspection
  -> snapshot restoration
~~

---

## Recovery Test State

Before creating the snapshot, recoverable Kubernetes state was created inside:

~~text
backup-test
~~

Resources included:

- Namespace
- ConfigMap
- Secret
- Deployment
- Pod

The ConfigMap contained a recovery marker used later to verify restored state.

The namespace UID was also recorded before the backup.

---

## Live etcd Snapshot

The etcd snapshot was written outside the Git workspace:

~~text
/opt/etcd-backup/
~~

The snapshot was created using authenticated TLS access to the running etcd server.

After creation it was:

- validated with `etcdutl snapshot status`
- protected with restrictive filesystem permissions
- hashed with SHA-256
- recorded in metadata evidence

The actual snapshot is intentionally excluded from source control.

---

## Why the Snapshot Is Not Stored in Git

An etcd snapshot contains Kubernetes backing state.

Depending on the cluster, that can include:

- Secrets
- ConfigMaps
- authentication material
- RBAC resources
- workload definitions
- service-account information
- application configuration

Only snapshot metadata and recovery evidence are included in the repository.

---

## Disaster-Recovery Simulation

A real recovery sequence was performed.

### Step 1 — Snapshot

A valid etcd snapshot was created while the recovery namespace existed.

### Step 2 — Simulated State Loss

The `backup-test` namespace and all contained resources were deleted.

The absence of the namespace was verified.

### Step 3 — Quiesce Control Plane Writes

The kube-apiserver static Pod manifest was temporarily moved out of:

~~text
/etc/kubernetes/manifests/
~~

This prevented API writes during etcd restoration.

### Step 4 — Stop etcd

The etcd static Pod manifest was moved out of the static Pod directory.

The runtime was checked to confirm the etcd container stopped.

### Step 5 — Preserve Existing etcd Data

The post-deletion `/var/lib/etcd` directory was moved aside instead of being deleted.

### Step 6 — Restore Snapshot

The snapshot was restored with `etcdutl`.

The restore reused the kubeadm etcd member configuration:

- member name
- initial cluster
- initial advertise peer URL
- data directory

### Step 7 — Restart etcd

The etcd static Pod manifest was restored.

The restored etcd endpoint was checked for health before continuing.

### Step 8 — Restart API Server

The kube-apiserver manifest was restored.

API readiness was verified through:

~~text
/readyz
~~

### Step 9 — Verify Recovered State

The previously deleted namespace returned.

Validation included:

- namespace existence
- namespace UID
- ConfigMap
- Secret
- Deployment
- Pod
- recovery marker value

This confirmed the Kubernetes state came from the restored etcd snapshot.

---

## etcd Recovery Procedure

A reference recovery workflow is included in:

~~text
etcd-recovery-procedure.sh
~~

The documented sequence covers:

1. Validate snapshot
2. Stop API server writes
3. Stop etcd
4. Preserve the existing etcd data directory
5. Restore with `etcdutl`
6. Restart etcd
7. Validate etcd health
8. Restart API server
9. Validate Kubernetes API readiness
10. Verify restored Kubernetes resources

The recovery script is deliberately documentation-oriented and should not be executed blindly against a production environment.

---

## Post-Recovery Cluster Health

After the restore, the control plane underwent comprehensive verification.

### API Server

Checked:

~~text
/readyz
/livez
kubectl cluster-info
~~

### Node

Validated:

- Ready condition
- node addresses
- control-plane role
- Pod CIDR
- kubelet status

### System Components

Inspected:

- kube-apiserver
- kube-controller-manager
- kube-scheduler
- etcd
- CoreDNS
- kube-proxy
- Flannel

### etcd

Checked:

~~bash
etcdctl member list
etcdctl endpoint health
etcdctl endpoint status
~~

### Static Pod Manifests

Validated:

~~text
/etc/kubernetes/manifests/etcd.yaml
/etc/kubernetes/manifests/kube-apiserver.yaml
/etc/kubernetes/manifests/kube-controller-manager.yaml
/etc/kubernetes/manifests/kube-scheduler.yaml
~~

---

## Service Connectivity Validation

A three-replica nginx workload and ClusterIP Service were deployed.

The validation checked:

- Deployment readiness
- Pod scheduling
- Service creation
- EndpointSlice population
- CoreDNS availability
- internal DNS resolution
- HTTP connectivity through the Service

A BusyBox client Pod performed the service request from inside the cluster.

This verified that the recovered cluster was not merely responding to administrative commands but was capable of normal workload networking.

---

## API Read/Write Verification

A temporary ConfigMap was created and deleted after recovery.

This confirmed that the restored API server and etcd backing store supported successful read/write operations.

---

## Reusable Health Check

The repository includes:

~~text
cluster-health-check.sh
~~

The script checks:

- API readiness
- node readiness
- system Pods
- Flannel
- etcd membership
- etcd endpoint health
- recent Kubernetes events

This provides a reusable operational validation workflow after control-plane maintenance or recovery.

---

## Troubleshooting Improvements

Several older operational patterns were intentionally modernized.

### Deprecated Component Status API

Instead of relying on:

~~bash
kubectl get componentstatuses
~~

the implementation validates:

- `/readyz`
- `/livez`
- node conditions
- static Pod status
- kube-system Pods
- direct etcd health

These checks provide more meaningful control-plane health evidence.

---

### Modern etcd Recovery

Snapshot creation and recovery use separate tools:

~~text
etcdctl -> snapshot save
etcdutl -> snapshot status / restore
~~

This matches current etcd operational practices.

---

### kubeadm etcd Ownership

The restore process does not assume an `etcd:etcd` system account.

kubeadm runs etcd as a static Pod, so recovery preserves the container-oriented kubeadm architecture instead of treating etcd as a standalone systemd service.

---

## Evidence Files

The implementation produces the following operational evidence:

~~text
environment-topology.txt
control-plane-installation-evidence.txt
worker-join-procedure.txt
worker-join-validation.txt
worker-scheduling-evidence.txt
etcd-snapshot-evidence.txt
etcd-disaster-recovery-evidence.txt
cluster-health-report.txt
post-recovery-cluster-evidence.txt
~~

Sensitive bootstrap tokens and actual etcd snapshots are intentionally excluded.

---

## Repository Structure

~~text
kubernetes-cluster-bootstrap-disaster-recovery/
├── README.md
├── environment-topology.txt
├── control-plane-installation-evidence.txt
├── worker-join-procedure.txt
├── worker-join-validation.txt
├── worker-scheduling-evidence.txt
├── scheduling-test.yaml
├── etcd-snapshot-evidence.txt
├── etcd-disaster-recovery-evidence.txt
├── etcd-recovery-procedure.sh
├── cluster-health-test.yaml
├── cluster-health-check.sh
├── cluster-health-report.txt
└── post-recovery-cluster-evidence.txt
~~

---

## Skills Demonstrated

- Kubernetes administration
- kubeadm
- Control-plane bootstrap
- containerd
- CRI troubleshooting
- kubelet
- kubectl
- Flannel CNI
- Linux networking
- Kernel module configuration
- Kubernetes node administration
- Bootstrap token management
- Worker join validation
- Kubernetes certificate discovery
- Pod scheduling
- etcd
- etcdctl
- etcdutl
- TLS-authenticated etcd administration
- etcd snapshots
- Kubernetes disaster recovery
- Static Pod administration
- API server recovery
- Cluster health diagnostics
- CoreDNS validation
- Kubernetes Service networking
- Operational evidence generation

---

## Operational Relevance

This implementation maps directly to real Kubernetes infrastructure responsibilities including:

- cluster bootstrap
- node onboarding
- runtime configuration
- CNI deployment
- control-plane troubleshooting
- cluster-state backup
- disaster recovery
- etcd administration
- infrastructure validation
- platform engineering
- SRE
- DevOps
- Kubernetes operations

The key result is not simply that a Kubernetes cluster was created.

The environment was taken through a complete operational lifecycle:

~~text
Fresh Host
   ->
Runtime Preparation
   ->
kubeadm Bootstrap
   ->
CNI Installation
   ->
Scheduling Validation
   ->
etcd Snapshot
   ->
Simulated State Loss
   ->
Control-Plane Recovery
   ->
State Restoration
   ->
Cluster Health Verification
~~

This demonstrates both cluster construction and recovery of the Kubernetes control plane after loss of stored cluster state.
