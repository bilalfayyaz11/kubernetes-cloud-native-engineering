# Kubernetes Cluster Bootstrap with kubeadm, containerd and Flannel

## What This Does

This implementation provisions a Kubernetes control plane from a clean Ubuntu host using kubeadm, containerd, and Flannel.

The host is prepared with the kernel modules, sysctl networking configuration, cgroup settings, container runtime integration, and Kubernetes components required for cluster operation.

The cluster runs as a single-node environment capable of scheduling workloads directly on the control-plane node. Kubernetes DNS, pod networking, API health endpoints, resource metrics, NodePort traffic, and workload lifecycle operations are validated end to end.

Rather than relying on a managed Kubernetes service, this implementation exposes the underlying bootstrap process and infrastructure dependencies required by kubeadm-based clusters.

## Architecture

~~text
┌───────────────────────────────────────────────────────────────┐
│                     Ubuntu 24.04 Host                         │
│                                                               │
│  Kernel / Networking                                          │
│  ├── overlay                                                  │
│  ├── br_netfilter                                             │
│  ├── IPv4 forwarding                                         │
│  └── bridge netfilter sysctls                                 │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                 containerd 2.x                         │  │
│  │             systemd cgroup driver                     │  │
│  └───────────────────────┬─────────────────────────────────┘  │
│                          │ CRI                                │
│  ┌───────────────────────▼─────────────────────────────────┐  │
│  │               Kubernetes Control Plane                 │  │
│  │                                                       │  │
│  │  kube-apiserver ─── etcd                              │  │
│  │        │                                              │  │
│  │        ├── kube-controller-manager                    │  │
│  │        ├── kube-scheduler                             │  │
│  │        └── kubelet                                    │  │
│  └───────────────────────┬─────────────────────────────────┘  │
│                          │                                    │
│             ┌────────────┴─────────────┐                      │
│             │                          │                      │
│     ┌───────▼────────┐       ┌────────▼────────┐             │
│     │ Flannel CNI    │       │    CoreDNS      │             │
│     │ 10.244.0.0/16  │       │ Cluster DNS     │             │
│     └───────┬────────┘       └─────────────────┘             │
│             │                                                 │
│     ┌───────▼─────────────────────────────────────────────┐   │
│     │                 Kubernetes Pods                    │   │
│     │                                                    │   │
│     │ Deployment → Pod → Service → NodePort → HTTP       │   │
│     └─────────────────────────────────────────────────────┘   │
│                                                               │
│     Metrics Server → kubelet metrics → kubectl top            │
└───────────────────────────────────────────────────────────────┘
~~

## Prerequisites

- Ubuntu 24.04 or compatible Linux distribution
- Minimum 2 CPU cores
- Minimum 2 GB RAM
- sudo or root privileges
- Internet connectivity
- curl
- ca-certificates
- GnuPG
- systemd
- containerd
- Kubernetes package repository access

Required Linux kernel modules:

~~text
overlay
br_netfilter
~~

Required sysctl values:

~~text
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
~~

Swap must be disabled before kubelet initialization.

## Setup & Installation

### Prepare the Host

~~bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo swapoff -a

cat <<'CONFIG' | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
CONFIG

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<'CONFIG' | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
CONFIG

sudo sysctl --system
~~

### Configure containerd

Generate a clean configuration for the installed containerd release:

~~bash
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
~~

For containerd 2.x, enable the systemd cgroup driver under the runc runtime configuration:

~~toml
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
SystemdCgroup = true
~~

Restart and enable containerd:

~~bash
sudo systemctl restart containerd
sudo systemctl enable containerd
~~

### Configure the Kubernetes Repository

~~bash
sudo mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key \
  | sudo gpg --dearmor \
  -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
~~

## How to Reproduce

### Initialize the Control Plane

~~bash
NODE_IP=$(hostname -I | awk '{print $1}')

sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address="$NODE_IP" \
  --cri-socket unix:///run/containerd/containerd.sock
~~

### Configure kubectl

~~bash
mkdir -p "$HOME/.kube"

sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

kubectl cluster-info
kubectl get nodes
~~

The node may initially report `NotReady` because pod networking has not yet been installed.

### Install Flannel

~~bash
kubectl apply \
  -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

kubectl wait \
  --for=condition=Ready \
  pod \
  --all \
  -n kube-flannel \
  --timeout=300s
~~

For a single-node cluster:

~~bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

kubectl wait \
  --for=condition=Ready \
  node \
  --all \
  --timeout=300s

kubectl get nodes -o wide
~~

### Verify Cluster Health

~~bash
kubectl get pods -A
kubectl cluster-info
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
~~

Validate DNS components:

~~bash
kubectl get deployment coredns -n kube-system
kubectl get pods -n kube-system -l k8s-app=kube-dns
~~

### Deploy a Workload

~~bash
kubectl create deployment nginx-test --image=nginx:latest

kubectl rollout status \
  deployment/nginx-test \
  --timeout=300s

kubectl expose deployment nginx-test \
  --port=80 \
  --target-port=80 \
  --type=NodePort
~~

Determine the node IP and allocated NodePort:

~~bash
NODE_IP=$(kubectl get node \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

NODE_PORT=$(kubectl get service nginx-test \
  -o jsonpath='{.spec.ports[0].nodePort}')
~~

Test the application:

~~bash
curl "http://${NODE_IP}:${NODE_PORT}"
~~

Test service discovery from inside the cluster:

~~bash
kubectl run nginx-client \
  --image=curlimages/curl:latest \
  --restart=Never \
  --rm \
  -i \
  --command -- \
  curl -sS http://nginx-test
~~

Clean up:

~~bash
kubectl delete deployment nginx-test
kubectl delete service nginx-test
~~

### Install Metrics Server

~~bash
kubectl apply \
  -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
~~

For this temporary kubeadm environment, Metrics Server was configured to accept the kubelet's self-signed serving certificate:

~~bash
kubectl patch deployment metrics-server \
  -n kube-system \
  --type='json' \
  -p='[
    {
      "op":"add",
      "path":"/spec/template/spec/containers/0/args/-",
      "value":"--kubelet-insecure-tls"
    }
  ]'
~~

This option is suitable for controlled development environments. Production deployments should use properly trusted kubelet serving certificates.

Verify resource metrics:

~~bash
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods -A
~~

### Verify DNS

~~bash
kubectl run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm \
  -i \
  --command -- \
  nslookup kubernetes.default.svc.cluster.local
~~

Validate external DNS:

~~bash
kubectl run dns-external-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm \
  -i \
  --command -- \
  nslookup github.com
~~

## Tools Used

- Ubuntu Linux
- Kubernetes 1.36
- kubeadm
- kubelet
- kubectl
- containerd 2.x
- Flannel
- CoreDNS
- Metrics Server
- systemd
- Linux kernel networking
- iptables with nftables backend
- curl
- GnuPG
- APT
- BusyBox
- NGINX

## Key Skills Demonstrated

- Bootstrapping Kubernetes without relying on a managed control plane
- Configuring containerd as the Kubernetes CRI runtime
- Aligning Linux cgroups with Kubernetes runtime requirements
- Configuring kernel modules and sysctl values for container networking
- Installing and validating CNI-based pod networking
- Diagnosing control-plane and kubelet health
- Working with Kubernetes Deployments, Pods, and Services
- Testing NodePort traffic and internal service discovery
- Validating Kubernetes API readiness and liveness endpoints
- Deploying and validating Metrics Server
- Inspecting Kubernetes API resources and cluster events
- Troubleshooting bootstrap-time networking and runtime dependencies

## Real-World Use Case

This implementation is relevant when organizations operate Kubernetes directly on virtual machines, bare-metal servers, private cloud infrastructure, edge systems, or environments where a managed Kubernetes control plane is unavailable or undesirable.

Understanding the bootstrap process also improves troubleshooting in managed Kubernetes platforms because kubelet, container runtimes, CNI networking, DNS, certificates, scheduling, metrics, and Kubernetes API behavior remain fundamental platform components.

## Lessons Learned

- Kubernetes depends heavily on correct Linux host preparation before kubeadm initialization.
- containerd 2.x configuration differs from older 1.x examples and requires version-aware runtime configuration.
- A `NotReady` node immediately after kubeadm initialization is expected until a compatible CNI establishes pod networking.
- Kubernetes API readiness and liveness endpoints are more useful than deprecated component status resources.
- Metrics Server requires correct kubelet certificate handling, and bypassing TLS validation should remain limited to controlled non-production environments.

## Troubleshooting Log

### Bridge netfilter sysctl values unavailable

The bridge networking sysctl keys were initially unavailable because `br_netfilter` was not loaded.

Resolution:

~~bash
sudo modprobe br_netfilter
~~

The module was persisted through:

~~text
/etc/modules-load.d/k8s.conf
~~

### Kubernetes repository pinned to an older release

The supplied configuration referenced Kubernetes v1.28 while the environment already contained kubectl v1.36.

Resolution:

The Kubernetes v1.36 `pkgs.k8s.io` repository was configured so kubeadm, kubelet, and kubectl remain aligned on the same minor release family.

### containerd configuration differences

Older containerd examples commonly modify `SystemdCgroup` using configuration paths associated with containerd 1.x.

Resolution:

A clean configuration matching the installed containerd 2.x release was generated and the systemd cgroup driver was enabled under the current CRI runtime hierarchy.

### Deprecated component health command

Older Kubernetes procedures use:

~~bash
kubectl get componentstatuses
~~

Resolution:

Control-plane health was validated using:

~~bash
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
~~

### NodePort validation

Testing a NodePort exclusively through `localhost` can produce misleading results depending on node networking behavior.

Resolution:

The Kubernetes node `InternalIP` and dynamically allocated NodePort were used for HTTP validation.

### Metrics Server kubelet TLS

Metrics Server can reject self-signed kubelet serving certificates in kubeadm bootstrap environments.

Resolution:

`--kubelet-insecure-tls` was used for this temporary single-node environment.

Production deployments should instead use correctly signed kubelet serving certificates.

### Outdated DNS test image

The supplied DNS verification used an older BusyBox image.

Resolution:

BusyBox 1.36 was used for Kubernetes service DNS and external DNS validation.
