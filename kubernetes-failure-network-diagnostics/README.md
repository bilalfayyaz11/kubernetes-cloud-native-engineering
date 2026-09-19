# Kubernetes Failure Diagnosis and Network Troubleshooting

## What This Does

This implementation provides a systematic Kubernetes troubleshooting workflow covering control-plane diagnostics, kubelet analysis, container image failures, workload inspection, Service connectivity, cluster DNS, and network-path troubleshooting. It combines native Kubernetes observability commands with reusable shell automation to identify root causes rather than relying only on resource status. Intentionally broken workloads are used to reproduce realistic operational failures, diagnose them through events and runtime state, and verify the corrected configuration. The resulting workflow provides a practical foundation for diagnosing Kubernetes incidents in production-style environments.

## Architecture

~~text
                           Kubernetes Cluster
                                  |
              +-------------------+-------------------+
              |                   |                   |
              v                   v                   v
      +---------------+   +---------------+   +---------------+
      | Control Plane |   | Node Runtime  |   | Cluster DNS   |
      |               |   |               |   |               |
      | kube-apiserver|   | kubelet       |   | CoreDNS       |
      | controller    |   | containerd    |   | Service DNS   |
      | scheduler     |   | CNI / Flannel |   | EndpointSlice |
      +-------+-------+   +-------+-------+   +-------+-------+
              |                   |                   |
              +-------------------+-------------------+
                                  |
                                  v
                     +-------------------------+
                     | Workload Troubleshooting|
                     +-------------------------+
                       |          |          |
                       v          v          v
                 failing-app  working-app  fixed-app
                 bad image    comparison   corrected
                       |
                       v
                ImagePullBackOff


                    Network Diagnostic Path
                    -----------------------

            client-pod  ----------------> server-pod
                |                           |
                |                           |
                +------> server-service <---+
                             |
                             v
                       EndpointSlice
                             |
                             v
                           CoreDNS

                             ^
                             |
                         debug-pod
                     nicolaka/netshoot
                             |
             +---------------+----------------+
             |               |                |
             v               v                v
           dig            traceroute        ip / ss
         nslookup          routing           curl
~~

## Prerequisites

- Ubuntu Linux
- sudo privileges
- Kubernetes cluster
- kubectl configured with administrator access
- kubeadm-based control plane for native component inspection
- containerd runtime
- Git
- curl
- wget
- ping
- traceroute
- dig
- nslookup
- netcat
- iproute2 networking tools
- Internet connectivity for container images

The validated environment used a single-node kubeadm Kubernetes cluster with Flannel networking.

## Setup & Installation

### Prepare the Host

Disable swap:

~~bash
sudo swapoff -a
~~

Load required kernel modules:

~~bash
sudo modprobe overlay
sudo modprobe br_netfilter
~~

Configure Kubernetes networking:

~~bash
cat <<'SYSCTL' | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYSCTL

sudo sysctl --system
~~

### Configure containerd

Generate the default configuration if needed:

~~bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
~~

Enable systemd cgroups:

~~bash
sudo sed -i \
  's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml

sudo systemctl restart containerd
~~

### Install Kubernetes Components

Configure the Kubernetes package repository appropriate for the desired Kubernetes minor version and install:

~~bash
sudo apt-get update

sudo apt-get install -y \
  kubelet \
  kubeadm \
  traceroute \
  conntrack \
  socat
~~

Initialize the control plane:

~~bash
NODE_IP="$(hostname -I | awk '{print $1}')"

sudo kubeadm init \
  --apiserver-advertise-address="$NODE_IP" \
  --pod-network-cidr=10.244.0.0/16
~~

Configure kubectl:

~~bash
mkdir -p "$HOME/.kube"

sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
~~

Install Flannel:

~~bash
kubectl apply -f \
  https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
~~

Allow workloads on the single-node control plane:

~~bash
kubectl taint nodes \
  --all \
  node-role.kubernetes.io/control-plane-
~~

Verify:

~~bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
~~

## How to Reproduce

### 1. Inspect Control-Plane Components

List system workloads:

~~bash
kubectl get pods -n kube-system -o wide
~~

Detect the API server:

~~bash
APISERVER_POD="$(kubectl get pods \
  -n kube-system \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | grep '^kube-apiserver-' \
  | head -1)"
~~

Read recent API-server logs:

~~bash
kubectl logs \
  -n kube-system \
  "$APISERVER_POD" \
  --tail=50
~~

Search for common failure indicators:

~~bash
kubectl logs \
  -n kube-system \
  "$APISERVER_POD" \
  --tail=500 \
  | grep -Ei 'error|failed|fatal|panic|timeout|denied'
~~

### 2. Inspect kubelet

Check the service:

~~bash
sudo systemctl status kubelet --no-pager
~~

Read recent logs:

~~bash
sudo journalctl \
  -u kubelet \
  --no-pager \
  --lines=50
~~

Filter suspicious messages:

~~bash
sudo journalctl \
  -u kubelet \
  --since "30 minutes ago" \
  --no-pager \
  | grep -Ei 'failed|error|warning|network|cni|runtime|pod'
~~

### 3. Run the Component Log Collector

The reusable collector gathers:

- cluster status
- node information
- system workload state
- Kubernetes events
- kubelet logs
- API-server logs
- controller-manager logs
- scheduler logs
- common error patterns

Run it with:

~~bash
chmod +x collect_k8s_logs.sh
./collect_k8s_logs.sh
~~

### 4. Reproduce an Image Pull Failure

Deploy the intentionally broken workload:

~~bash
kubectl apply -f failing-pod.yaml
~~

Observe its state:

~~bash
kubectl get pod failing-app
~~

Inspect detailed events:

~~bash
kubectl describe pod failing-app
~~

The workload references:

~~text
nginx:nonexistent-tag
~~

The container runtime cannot retrieve that image, producing states such as:

~~text
ErrImagePull
ImagePullBackOff
~~

### 5. Inspect the Failure Systematically

Inspect the Events section:

~~bash
kubectl describe pod failing-app \
  | sed -n '/Events:/,$p'
~~

Inspect the waiting reason:

~~bash
kubectl get pod failing-app \
  -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}'
~~

Attempting container logs may fail because the container never started:

~~bash
kubectl logs failing-app
~~

That itself is useful diagnostic evidence: image acquisition failed before application execution.

### 6. Deploy a Healthy Comparison

Create the working workload:

~~bash
kubectl apply -f working-pod.yaml
~~

Wait for readiness:

~~bash
kubectl wait \
  --for=condition=Ready \
  pod/working-app \
  --timeout=180s
~~

Compare states:

~~bash
kubectl get pods \
  failing-app \
  working-app \
  -o wide
~~

Inspect the healthy container:

~~bash
kubectl exec working-app -- whoami
kubectl exec working-app -- hostname
kubectl exec working-app -- nginx -v
~~

Verify NGINX locally:

~~bash
kubectl exec working-app -- \
  sh -c 'wget -qO- http://127.0.0.1 | head'
~~

### 7. Apply the Corrected Workload

Remove the failed instance:

~~bash
kubectl delete pod failing-app
~~

Deploy the corrected definition:

~~bash
kubectl apply -f fixed-pod.yaml
~~

Wait for readiness:

~~bash
kubectl wait \
  --for=condition=Ready \
  pod/fixed-app \
  --timeout=180s
~~

Verify:

~~bash
kubectl get pod fixed-app -o wide
~~

### 8. Build the Network Test Environment

Deploy the client, server, and ClusterIP Service:

~~bash
kubectl apply -f network-test-pods.yaml
~~

Wait for the workloads:

~~bash
kubectl wait \
  --for=condition=Ready \
  pod/client-pod \
  pod/server-pod \
  --timeout=180s
~~

Inspect addresses:

~~bash
kubectl get pods \
  -l app=network-test \
  -o wide

kubectl get service server-service -o wide
~~

### 9. Test Pod-to-Pod Connectivity

Capture the server Pod IP:

~~bash
SERVER_POD_IP="$(kubectl get pod server-pod \
  -o jsonpath='{.status.podIP}')"
~~

Test ICMP:

~~bash
kubectl exec client-pod -- \
  ping -c 4 "$SERVER_POD_IP"
~~

Test application traffic directly:

~~bash
kubectl exec client-pod -- \
  wget -qO- \
  "http://$SERVER_POD_IP"
~~

Test TCP port 80:

~~bash
kubectl exec client-pod -- \
  nc -zvw5 "$SERVER_POD_IP" 80
~~

### 10. Test Kubernetes Service Routing

Inspect the Service:

~~bash
kubectl describe service server-service
~~

Inspect its EndpointSlice:

~~bash
kubectl get endpointslice \
  -l kubernetes.io/service-name=server-service \
  -o wide
~~

Test using the Service DNS name:

~~bash
kubectl exec client-pod -- \
  wget -qO- http://server-service
~~

Test using its ClusterIP:

~~bash
SERVICE_IP="$(kubectl get service server-service \
  -o jsonpath='{.spec.clusterIP}')"

kubectl exec client-pod -- \
  wget -qO- "http://$SERVICE_IP"
~~

A ClusterIP should be tested using the Service's configured application protocol and port rather than treating it as a normal host address.

### 11. Deploy the Advanced Network Debug Container

Deploy Netshoot:

~~bash
kubectl apply -f debug-pod.yaml
~~

Wait for readiness:

~~bash
kubectl wait \
  --for=condition=Ready \
  pod/debug-pod \
  --timeout=180s
~~

Netshoot provides utilities such as:

- curl
- dig
- nslookup
- traceroute
- ip
- ss
- tcpdump
- networking diagnostics

### 12. Troubleshoot Cluster DNS

Resolve the Service short name:

~~bash
kubectl exec debug-pod -- \
  nslookup server-service
~~

Resolve its full Kubernetes DNS name:

~~bash
kubectl exec debug-pod -- \
  nslookup server-service.default.svc.cluster.local
~~

Resolve the built-in Kubernetes Service:

~~bash
kubectl exec debug-pod -- \
  nslookup kubernetes.default.svc.cluster.local
~~

Inspect resolver configuration:

~~bash
kubectl exec debug-pod -- \
  cat /etc/resolv.conf
~~

Inspect CoreDNS:

~~bash
kubectl get pods \
  -n kube-system \
  -l k8s-app=kube-dns \
  -o wide

kubectl logs \
  -n kube-system \
  -l k8s-app=kube-dns \
  --tail=50
~~

### 13. Analyze Network Paths and Interfaces

Trace the path to the server:

~~bash
kubectl exec debug-pod -- \
  traceroute "$SERVER_POD_IP"
~~

Inspect interfaces:

~~bash
kubectl exec debug-pod -- \
  ip addr show
~~

Inspect routing:

~~bash
kubectl exec debug-pod -- \
  ip route show
~~

Inspect listening sockets:

~~bash
kubectl exec debug-pod -- \
  ss -tuln
~~

Verify application connectivity:

~~bash
kubectl exec debug-pod -- \
  curl -fsS http://server-service
~~

### 14. Run the Reusable Network Troubleshooter

The network troubleshooting script gathers and validates:

- node status
- Pod addresses
- Services
- EndpointSlices
- Pod-to-Pod connectivity
- direct HTTP connectivity
- ClusterIP routing
- Service DNS
- Kubernetes DNS
- resolver configuration
- CoreDNS state
- routing information

Run it with:

~~bash
chmod +x network_troubleshoot.sh
./network_troubleshoot.sh
~~

## Tools Used

- Kubernetes
- kubeadm
- kubelet
- kube-apiserver
- kube-controller-manager
- kube-scheduler
- kubectl
- containerd
- Flannel
- CoreDNS
- EndpointSlice
- NGINX
- BusyBox
- Netshoot
- journalctl
- systemctl
- ping
- traceroute
- curl
- wget
- netcat
- dig
- nslookup
- iproute2
- ss
- Git

## Key Skills Demonstrated

- Kubernetes control-plane troubleshooting
- kube-apiserver log analysis
- kubelet and systemd journal inspection
- Kubernetes event analysis
- Container image failure diagnosis
- `ImagePullBackOff` root-cause analysis
- Pod lifecycle troubleshooting
- Runtime inspection with `kubectl exec`
- Healthy-versus-failing workload comparison
- Pod-to-Pod network testing
- ClusterIP Service troubleshooting
- EndpointSlice inspection
- Kubernetes DNS troubleshooting
- CoreDNS diagnosis
- Pod routing analysis
- Network interface inspection
- TCP and HTTP connectivity validation
- Traceroute-based path analysis
- Reusable troubleshooting automation
- Failure-safe remote execution practices

## Real-World Use Case

This troubleshooting workflow applies to Kubernetes environments where workloads fail to start, applications cannot reach each other, Services appear unavailable, DNS resolution fails, or control-plane and node components produce unexpected behavior. Platform and reliability engineers need to distinguish whether a symptom originates from workload configuration, image distribution, scheduling, runtime state, Service selection, cluster DNS, CNI routing, or control-plane behavior. Combining resource inspection, component logs, events, runtime diagnostics, and network testing provides a repeatable method for isolating failures and reducing incident resolution time.

## Lessons Learned

- Resource status alone rarely provides enough information to identify a Kubernetes failure.
- Kubernetes Events are often the fastest path to diagnosing scheduling and image-related problems.
- A container that never starts may have no application logs, making Events and container state more important than `kubectl logs`.
- Comparing a failing workload against a known-good equivalent helps isolate configuration differences quickly.
- Kubernetes Service connectivity should be tested at the application protocol and port rather than by assuming a virtual ClusterIP behaves like a regular host.
- EndpointSlices show whether a Service actually has healthy selected backends.
- DNS troubleshooting should validate both the application Service and the built-in Kubernetes Service.
- CoreDNS health, Pod resolver configuration, and Service selectors are separate troubleshooting layers.
- Control-plane and kubelet logs provide different perspectives and should be inspected together.
- Reusable diagnostics reduce troubleshooting time and make investigations more consistent.
- Remote shell automation should preserve the parent SSH session when expected diagnostic failures occur.

## Troubleshooting Log

### No Kubernetes Cluster Present

The fresh environment contained kubectl but had no active context, kubelet, kubeadm, or control-plane components.

Resolution:

- configured containerd
- installed kubelet and kubeadm
- initialized a kubeadm control plane
- configured kubectl
- installed Flannel networking
- enabled workloads on the single-node control plane

### Static API Server Discovery

Hard-coding the API-server name to the local hostname can fail when naming differs.

Resolution:

The API-server Pod is detected dynamically:

~~bash
APISERVER_POD="$(kubectl get pods \
  -n kube-system \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | grep '^kube-apiserver-' \
  | head -1)"
~~

### Intentional Image Pull Failure

The failing workload referenced:

~~text
nginx:nonexistent-tag
~~

Observed state:

~~text
ErrImagePull
ImagePullBackOff
~~

Root cause:

The requested container image tag did not exist.

Resolution:

- inspected Pod Events
- inspected waiting state
- compared against a healthy NGINX workload
- replaced the invalid image reference
- confirmed the corrected Pod reached Ready state

### No Application Logs for Failed Container

`kubectl logs failing-app` could not provide useful application output because the container never started.

Resolution:

Used:

- `kubectl describe`
- Events
- `.status.containerStatuses`
- image configuration

to diagnose the failure before container execution.

### ClusterIP Ping Assumption

ICMP against a Kubernetes ClusterIP is not a reliable Service health test.

Resolution:

Validated the Service using:

~~bash
wget http://server-service
~~

and:

~~bash
wget "http://$SERVICE_IP"
~~

along with TCP port checks and EndpointSlice inspection.

### Service Backend Verification

Service configuration alone does not prove that healthy backends exist.

Resolution:

Used:

~~bash
kubectl get endpointslice \
  -l kubernetes.io/service-name=server-service
~~

to verify the actual selected backend.

### DNS Troubleshooting

Service resolution was validated using both:

~~text
server-service
~~

and:

~~text
server-service.default.svc.cluster.local
~~

The built-in Kubernetes Service was also resolved to verify cluster-wide DNS functionality.

### Remote Session Safety

Previous remote workflows demonstrated that `set -e` can terminate an SSH shell when a diagnostic command returns a non-zero code.

Resolution:

- used `set +e`
- wrapped larger workflows in functions
- handled expected failures explicitly
- used `return` instead of terminating the parent shell
- preserved the SSH session during troubleshooting

## Repository Contents

~~text
.
├── README.md
├── collect_k8s_logs.sh
├── component-log-analysis.txt
├── failing-pod.yaml
├── fixed-pod.yaml
├── pod-debugging-evidence.txt
├── working-pod.yaml
├── network-test-pods.yaml
├── debug-pod.yaml
├── network_troubleshoot.sh
└── network-troubleshooting-evidence.txt
~~
