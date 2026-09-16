# Kubernetes Pod Security and Network Microsegmentation

## What This Does

This implementation applies layered workload and network security controls to a Kubernetes environment using Pod Security Admission and Calico NetworkPolicy enforcement.

Pod Security Admission is configured at the namespace level using Baseline and Restricted security standards. Workloads are tested against these policies to prove that insecure configurations are rejected while compliant workloads are admitted.

A three-tier frontend, backend, and database topology is then protected using default-deny and explicit allow NetworkPolicies. Connectivity is tested before and after enforcement to prove that legitimate application paths remain available while unauthorized lateral and external communication is blocked.

## Architecture

    +------------------------------------------------------------------+
    |                    Kubernetes Security Stack                      |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                    POD SECURITY ADMISSION                         |
    |                                                                  |
    |  security-demo                                                   |
    |    Policy: Baseline                                              |
    |       |                                                          |
    |       +--> Normal workload                ALLOWED                 |
    |       +--> Privileged workload            DENIED                  |
    |                                                                  |
    |  restricted-demo                                                 |
    |    Policy: Restricted                                            |
    |       |                                                          |
    |       +--> Non-root workload              ALLOWED                 |
    |       +--> RuntimeDefault seccomp                                 |
    |       +--> No privilege escalation                               |
    |       +--> ALL capabilities dropped                              |
    |       +--> Insufficiently hardened pod    DENIED                  |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                   APPLICATION TOPOLOGY                            |
    |                                                                  |
    |  +---------------+      +---------------+      +--------------+   |
    |  |   frontend    |      |    backend    |      |   database   |   |
    |  |               |      |               |      |              |   |
    |  | nginx         | ---> | Apache HTTP   | ---> | MySQL        |   |
    |  | port 80 svc   |      | port 80 svc   |      | port 3306    |   |
    |  +---------------+      +---------------+      +--------------+   |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                    CALICO NETWORK POLICY                          |
    |                                                                  |
    |  frontend -> backend:80               ALLOWED                    |
    |  backend  -> database:3306            ALLOWED                    |
    |  backend  -> CoreDNS:53               ALLOWED                    |
    |                                                                  |
    |  frontend -> database:3306            BLOCKED                    |
    |  default  -> database:3306            BLOCKED                    |
    |  backend  -> frontend:80              BLOCKED                    |
    |  backend  -> external HTTPS           BLOCKED                    |
    +------------------------------------------------------------------+

## Prerequisites

- Linux environment
- Docker Engine
- Minikube
- kubectl
- Kubernetes cluster with Pod Security Admission
- Calico or another NetworkPolicy-capable CNI
- curl
- jq
- OpenSSL
- Bash

Recommended local resources:

- 2 CPU cores
- 3 GB RAM or more
- 10 GB or more available storage

## Environment Setup

Install Docker if required:

    sudo apt-get update
    sudo apt-get install -y docker.io ca-certificates curl conntrack

Enable Docker:

    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"

Install Minikube:

    curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm -f minikube-linux-amd64

Start Kubernetes with Calico:

    minikube start \
      --driver=docker \
      --container-runtime=containerd \
      --cni=calico \
      --cpus=2 \
      --memory=2800mb

Verify:

    kubectl cluster-info
    kubectl get nodes -o wide
    kubectl get pods -A | grep -Ei 'calico|tigera'

## How to Reproduce

### 1. Configure Baseline Pod Security Admission

Create the namespace:

    kubectl create namespace security-demo

Apply Baseline Pod Security labels:

    kubectl label namespace security-demo \
      pod-security.kubernetes.io/enforce=baseline \
      pod-security.kubernetes.io/audit=baseline \
      pod-security.kubernetes.io/warn=baseline

Deploy:

    kubectl apply -f baseline-allowed-pod.yaml

The Baseline-compliant workload should be admitted.

Test a privileged workload:

    kubectl apply -f baseline-rejected-pod.yaml

Expected result:

    Pod rejected by Pod Security Admission

### 2. Configure Restricted Pod Security Admission

Create:

    kubectl create namespace restricted-demo

Apply Restricted policy:

    kubectl label namespace restricted-demo \
      pod-security.kubernetes.io/enforce=restricted \
      pod-security.kubernetes.io/audit=restricted \
      pod-security.kubernetes.io/warn=restricted

Deploy:

    kubectl apply -f restricted-compliant-pod.yaml

The workload implements:

- runAsNonRoot
- RuntimeDefault seccomp
- allowPrivilegeEscalation=false
- readOnlyRootFilesystem
- ALL Linux capabilities dropped

An insufficiently hardened pod should be rejected by the Restricted policy.

### 3. Create Three-Tier Namespaces

Create:

    kubectl create namespace frontend
    kubectl create namespace backend
    kubectl create namespace database

Label:

    kubectl label namespace frontend tier=frontend
    kubectl label namespace backend tier=backend
    kubectl label namespace database tier=database

### 4. Deploy Application Tiers

Apply:

    kubectl apply -f frontend-app.yaml
    kubectl apply -f backend-app.yaml
    kubectl apply -f database-app.yaml

The topology consists of:

- frontend web tier
- backend application tier
- MySQL database tier

The MySQL root credential is stored in a Kubernetes Secret rather than embedded directly in the Deployment manifest.

### 5. Deploy Diagnostic Pods

Apply:

    kubectl apply -f frontend-netcheck.yaml
    kubectl apply -f backend-netcheck.yaml

These diagnostic pods provide networking tools such as:

- curl
- nc
- nslookup
- dig

This avoids depending on application container images for connectivity testing.

## Baseline Connectivity

Before NetworkPolicies are applied, confirm:

    frontend -> backend
    backend -> database
    frontend -> database

All paths should initially be reachable.

Example:

    kubectl exec \
      -n frontend \
      frontend-netcheck \
      -- curl http://backend-service.backend.svc.cluster.local

    kubectl exec \
      -n backend \
      backend-netcheck \
      -- nc -zvw5 database-service.database.svc.cluster.local 3306

## NetworkPolicy Configuration

### Database Default Deny

Apply:

    kubectl apply -f database-default-deny.yaml

This isolates every pod in the database namespace for both:

- ingress
- egress

### Allow Backend to Database

Apply:

    kubectl apply -f allow-backend-to-database.yaml

Permitted traffic:

    source namespace: tier=backend
    destination pod: app=database
    protocol: TCP
    port: 3306

### Allow Database DNS

Apply:

    kubectl apply -f allow-database-dns.yaml

Database workloads may only send DNS traffic to CoreDNS on:

    UDP/53
    TCP/53

The policy targets CoreDNS specifically rather than allowing arbitrary port 53 traffic.

### Allow Frontend to Backend

Apply:

    kubectl apply -f allow-frontend-to-backend.yaml

Permitted traffic:

    source namespace: tier=frontend
    destination pod: app=backend
    TCP/80

### Restrict Backend Egress

Apply:

    kubectl apply -f backend-egress-policy.yaml

Backend workloads may initiate traffic only to:

- database pods on TCP/3306
- CoreDNS on TCP/UDP 53

Other egress is denied.

## Connectivity Validation

Expected final matrix:

    frontend -> backend:80             ALLOWED
    backend  -> database:3306          ALLOWED
    backend  -> CoreDNS:53             ALLOWED

    frontend -> database:3306          BLOCKED
    default  -> database:3306          BLOCKED
    backend  -> frontend:80            BLOCKED
    backend  -> external HTTPS         BLOCKED

### Allowed Path Test

    kubectl exec \
      -n frontend \
      frontend-netcheck \
      -- curl \
      --connect-timeout 5 \
      http://backend-service.backend.svc.cluster.local

### Database Path Test

    kubectl exec \
      -n backend \
      backend-netcheck \
      -- nc \
      -zvw5 \
      database-service.database.svc.cluster.local \
      3306

### Blocked Frontend-to-Database Test

    kubectl exec \
      -n frontend \
      frontend-netcheck \
      -- nc \
      -zvw5 \
      database-service.database.svc.cluster.local \
      3306

Expected result:

    timeout / connection failure

### Blocked Backend External Egress Test

    kubectl exec \
      -n backend \
      backend-netcheck \
      -- curl \
      --connect-timeout 5 \
      https://example.com

Expected result:

    connection blocked

## Tools Used

- Kubernetes
- kubectl
- Minikube
- Docker
- containerd
- Calico
- Pod Security Admission
- Pod Security Standards
- Kubernetes NetworkPolicy
- Kubernetes Secrets
- nginx
- Apache HTTP Server
- MySQL
- Netshoot
- curl
- netcat
- DNS utilities
- Bash

## Key Skills Demonstrated

- Kubernetes Pod Security Admission
- Baseline Pod Security Standard
- Restricted Pod Security Standard
- Namespace-level security enforcement
- Kubernetes SecurityContext configuration
- Non-root workload execution
- Linux capability restriction
- Seccomp configuration
- Privilege escalation prevention
- Kubernetes NetworkPolicy
- East-west traffic control
- Network microsegmentation
- Default-deny architecture
- Explicit allow-list design
- NamespaceSelector usage
- PodSelector usage
- Ingress security controls
- Egress security controls
- DNS-aware NetworkPolicy design
- Kubernetes service discovery
- Connectivity testing
- Calico policy enforcement
- Kubernetes networking troubleshooting

## Real-World Use Case

A platform or DevSecOps engineering team can use this design to enforce security boundaries across shared Kubernetes environments.

Pod Security Admission prevents application teams from deploying workloads with dangerous runtime configurations such as privileged containers or unrestricted Linux capabilities.

NetworkPolicy adds segmentation between application tiers. A compromised frontend workload cannot directly access the database, while backend services retain only the communication paths required for application operation.

Restricting backend egress also reduces command-and-control, data exfiltration, and lateral movement opportunities after a workload compromise.

Together these controls reduce blast radius without requiring changes to application code.

## Security Controls Implemented

### Pod Security

- Namespace-scoped PSA enforcement
- Baseline security policy
- Restricted security policy
- Non-root execution
- RuntimeDefault seccomp
- Read-only root filesystem
- Dropped Linux capabilities
- Disabled privilege escalation

### Network Security

- Default-deny ingress
- Default-deny egress
- Explicit frontend-to-backend access
- Explicit backend-to-database access
- Restricted backend egress
- Restricted database DNS egress
- Cross-namespace isolation
- External egress control

### Credential Security

- MySQL password stored in Kubernetes Secret
- No database password embedded directly in Deployment YAML

### Validation

- Allowed workload admission tests
- Rejected workload admission tests
- Pre-policy connectivity baseline
- Post-policy connectivity testing
- Unauthorized path testing
- External egress testing
- DNS validation
- Calico enforcement verification

## Lessons Learned

- Pod Security Admission controls workload configuration but does not control workload network communication.

- NetworkPolicy controls traffic only for pods selected by the policy's podSelector.

- A valid NetworkPolicy resource does not guarantee enforcement; the cluster CNI must support NetworkPolicy.

- Calico provides enforcement that can be validated through behavioral connectivity testing.

- A default-deny policy provides a safer foundation than attempting to blacklist unwanted communication paths individually.

- Explicit allow rules make permitted application dependencies easier to reason about.

- DNS access must be considered when implementing egress restrictions because service discovery depends on CoreDNS.

- Broad DNS policies using unrestricted destinations on port 53 allow more traffic than necessary.

- Diagnostic workloads should match the same selectors as application workloads when testing selector-based NetworkPolicies.

- Connectivity tests from an unselected diagnostic pod can falsely make a correct policy appear ineffective.

- Container runtime hardening must remain compatible with the application image. Arbitrary non-root UIDs can break software that expects writable runtime paths.

- Behavioral validation is stronger evidence of NetworkPolicy enforcement than simply listing policy resources.

## Troubleshooting Log

### Kubernetes Cluster Was Missing

The environment initially contained kubectl but no Kubernetes cluster.

Resolution:

Minikube was installed and initialized using Docker with Calico:

    minikube start \
      --driver=docker \
      --container-runtime=containerd \
      --cni=calico

### NetworkPolicy Enforcement Required a Compatible CNI

NetworkPolicy resources alone do not enforce traffic.

Resolution:

Calico was configured as the cluster CNI before application deployment.

### Restricted nginx Configuration Could Fail

Running the standard nginx image using arbitrary non-root user configuration and a read-only root filesystem can cause runtime permission failures.

Resolution:

The Restricted workload used an unprivileged nginx image designed for non-root execution.

### Plaintext Database Password Removed

The original database configuration embedded the MySQL root password directly in the Deployment manifest.

Resolution:

A Kubernetes Secret was generated and referenced through envFrom.

### Backend Workload Crashed

The initial backend hardening forced Apache to run as UID 1000.

Observed error:

    Permission denied:
    could not create /usr/local/apache2/logs/httpd.pid

Resolution:

The unsupported arbitrary UID override was removed and the backend workload was redeployed using a configuration compatible with the Apache container image.

### Backend Egress Policy Appeared Ineffective

The backend NetworkPolicy selected:

    app=backend

but the diagnostic pod was labeled:

    app=backend-netcheck

The diagnostic pod therefore remained outside the policy.

Resolution:

The diagnostic pod label was updated:

    kubectl label pod backend-netcheck \
      -n backend \
      app=backend \
      --overwrite

After the label matched the selector:

    backend -> database        ALLOWED
    backend -> DNS             ALLOWED
    backend -> frontend        BLOCKED
    backend -> external HTTPS  BLOCKED

### Calico Deny Logs Were Not Required for Proof

NetworkPolicy engines do not necessarily emit an easily readable log entry for every dropped packet by default.

Resolution:

Policy effectiveness was validated behaviorally by testing both authorized and unauthorized network paths.

## Outcome

This implementation establishes a defense-in-depth Kubernetes workload security model combining admission control with network microsegmentation.

The final environment demonstrates:

- Baseline Pod Security enforcement
- Restricted Pod Security enforcement
- Secure workload admission
- Privileged workload rejection
- Default-deny networking
- Explicit application communication paths
- Database isolation
- Backend egress restriction
- DNS preservation
- External egress blocking
- Calico NetworkPolicy enforcement
- End-to-end behavioral validation

These capabilities are directly applicable to DevSecOps, Kubernetes security, AIOps, platform engineering, and cloud-native infrastructure roles.
