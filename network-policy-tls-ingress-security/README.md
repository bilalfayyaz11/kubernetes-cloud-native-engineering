# Kubernetes Network Segmentation and TLS Ingress Security

## What This Does

This implementation secures a three-tier Kubernetes workload using namespace-level traffic segmentation, least-privilege NetworkPolicies, TLS termination, and controlled ingress routing. Frontend, backend, and database workloads operate in dedicated namespaces with explicitly authorized communication paths. Unauthorized lateral traffic is denied while required application flows remain operational. External requests are routed through NGINX Ingress with HTTPS termination and automatic HTTP-to-HTTPS redirection.

## Architecture

```text
                           External Client
                                  |
                         HTTP / HTTPS Traffic
                                  |
                                  v
                  +-----------------------------+
                  |    NGINX Ingress Controller |
                  |-----------------------------|
                  | TLS Termination             |
                  | HTTP -> HTTPS Redirect      |
                  | Host: secure-app.local      |
                  +--------------+--------------+
                                 |
                                 | HTTPS Routing
                                 v
+-----------------------------------------------------------------------+
|                         Kubernetes Cluster                            |
|                                                                       |
|  +----------------------- frontend namespace ----------------------+   |
|  |                                                                 |   |
|  |   +--------------------+       +-----------------------------+  |   |
|  |   | web-frontend       |<------| secure-app-ingress          |  |   |
|  |   | nginx              |       | TLS: secure-app-tls         |  |   |
|  |   +---------+----------+       +-----------------------------+  |   |
|  |             |                                                   |   |
|  +-------------|---------------------------------------------------+   |
|                | TCP/80 ALLOWED                                       |
|                v                                                       |
|  +------------------------ backend namespace ----------------------+   |
|  |                                                                  |   |
|  |   +--------------------+                                         |   |
|  |   | api-backend        |                                         |   |
|  |   | Apache HTTP Server |                                         |   |
|  |   +---------+----------+                                         |   |
|  |             |                                                    |   |
|  +-------------|----------------------------------------------------+   |
|                | TCP/5432 ALLOWED                                      |
|                v                                                        |
|  +----------------------- database namespace ----------------------+   |
|  |                                                                  |   |
|  |   +--------------------+                                         |   |
|  |   | db-server          |                                         |   |
|  |   | PostgreSQL 13      |                                         |   |
|  |   +--------------------+                                         |   |
|  |                                                                  |   |
|  +------------------------------------------------------------------+   |
|                                                                       |
|  Enforced Network Boundaries                                          |
|  ---------------------------------------------------------------      |
|  frontend      -> backend       ALLOWED TCP/80                         |
|  backend       -> database      ALLOWED TCP/5432                       |
|  frontend      -> database      BLOCKED                                |
|  untrusted     -> backend       BLOCKED                                |
|  untrusted     -> database      BLOCKED                                |
|                                                                       |
|  Restricted namespace DNS egress -> kube-system TCP/UDP 53             |
+-----------------------------------------------------------------------+
```

## Prerequisites

- Ubuntu or another supported Linux distribution
- Administrative sudo access
- Kubernetes cluster with NetworkPolicy-capable networking
- kubectl
- Git
- curl
- wget
- OpenSSL
- NGINX Ingress Controller
- Kubernetes `networking.k8s.io/v1` NetworkPolicy API
- Kubernetes `networking.k8s.io/v1` Ingress API
- Permissions to create namespaces, Deployments, Services, Secrets, NetworkPolicies, and Ingress resources

The implementation was validated on a lightweight single-node K3s cluster.

## Setup & Installation

### Kubernetes Cluster

A lightweight K3s installation can be used when an existing Kubernetes cluster is unavailable.

```bash
curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh

sudo sh /tmp/install-k3s.sh \
  --disable=traefik \
  --write-kubeconfig-mode=644

mkdir -p "$HOME/.kube"

sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

export KUBECONFIG="$HOME/.kube/config"

kubectl get nodes -o wide
```

Traefik is disabled so NGINX operates as the dedicated ingress implementation.

### NGINX Ingress Controller

```bash
git clone \
  --depth 1 \
  --branch v5.6.3 \
  https://github.com/nginx/kubernetes-ingress.git \
  ~/nginx-kubernetes-ingress

cd ~/nginx-kubernetes-ingress

kubectl apply -f deployments/common/ns-and-sa.yaml
kubectl apply -f deployments/rbac/rbac.yaml
kubectl apply -f deployments/common/nginx-config.yaml
kubectl apply -f deployments/common/ingress-class.yaml

kubectl apply -f \
  https://raw.githubusercontent.com/nginx/kubernetes-ingress/v5.6.3/deploy/crds.yaml

kubectl apply -f deployments/deployment/nginx-ingress.yaml

kubectl rollout status \
  deployment/nginx-ingress \
  -n nginx-ingress \
  --timeout=180s

kubectl apply -f deployments/service/nodeport.yaml

kubectl get pods -n nginx-ingress
kubectl get svc -n nginx-ingress
kubectl get ingressclass
```

## How to Reproduce

### 1. Create the Application Namespaces

```bash
kubectl create namespace frontend
kubectl create namespace backend
kubectl create namespace database

kubectl label namespace frontend name=frontend --overwrite
kubectl label namespace backend name=backend --overwrite
kubectl label namespace database name=database --overwrite
```

### 2. Deploy the Frontend

```bash
kubectl create deployment web-frontend \
  --image=nginx:latest \
  -n frontend

kubectl expose deployment web-frontend \
  --name=web-frontend \
  --port=80 \
  --target-port=80 \
  -n frontend
```

### 3. Deploy the Backend

```bash
kubectl create deployment api-backend \
  --image=httpd:latest \
  -n backend

kubectl expose deployment api-backend \
  --name=api-backend \
  --port=80 \
  --target-port=80 \
  -n backend
```

### 4. Deploy PostgreSQL

Apply the included database workload:

```bash
kubectl apply -f postgres-deployment.yaml

kubectl expose deployment db-server \
  --name=db-server \
  --port=5432 \
  --target-port=5432 \
  -n database
```

For production environments, database credentials should be supplied through an external secret-management platform or Kubernetes Secret rather than committed as plaintext configuration.

### 5. Verify Baseline Connectivity

Before NetworkPolicies are applied, verify that cross-namespace routing functions normally.

Expected baseline communication:

```text
frontend -> backend    ALLOWED
backend  -> database   ALLOWED
frontend -> database   ALLOWED
database -> backend    ALLOWED
```

This establishes the control state used to prove that subsequent traffic restrictions are caused by NetworkPolicy enforcement.

### 6. Apply Network Segmentation

```bash
kubectl apply -f frontend-network-policy.yaml
kubectl apply -f backend-network-policy.yaml
kubectl apply -f database-network-policy.yaml

kubectl get networkpolicy --all-namespaces
```

The resulting communication model is:

```text
frontend -> backend      ALLOWED
backend  -> database     ALLOWED
frontend -> database     BLOCKED
untrusted -> backend     BLOCKED
untrusted -> database    BLOCKED
```

Frontend and backend workloads retain DNS access to the `kube-system` namespace over both UDP and TCP port 53.

### 7. Generate a SAN-Enabled TLS Certificate

The included OpenSSL configuration defines `secure-app.local` as both the certificate common name and Subject Alternative Name.

```bash
openssl genrsa -out tls.key 2048

openssl req \
  -new \
  -key tls.key \
  -out tls.csr \
  -config tls-openssl.cnf

openssl x509 \
  -req \
  -in tls.csr \
  -signkey tls.key \
  -out tls.crt \
  -days 365 \
  -sha256 \
  -extensions req_ext \
  -extfile tls-openssl.cnf
```

Validate the resulting certificate:

```bash
openssl x509 \
  -in tls.crt \
  -noout \
  -subject \
  -issuer \
  -dates \
  -ext subjectAltName
```

Certificate private keys and generated certificate material must remain outside source control.

### 8. Create the Kubernetes TLS Secret

```bash
kubectl create secret tls secure-app-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n frontend
```

Verify it:

```bash
kubectl get secret secure-app-tls -n frontend
```

### 9. Apply Secure Ingress Routing

```bash
kubectl apply -f secure-ingress.yaml

kubectl get ingress secure-app-ingress \
  -n frontend \
  -o wide

kubectl describe ingress secure-app-ingress \
  -n frontend
```

The Ingress routes requests for:

```text
secure-app.local
```

to:

```text
web-frontend:80
```

and terminates TLS using:

```text
secure-app-tls
```

### 10. Configure Local Resolution

Determine the Kubernetes node address:

```bash
kubectl get nodes -o wide
```

Then map the application hostname to the node:

```text
<NODE-IP> secure-app.local
```

### 11. Validate HTTPS Routing

Determine the NGINX NodePort assignments:

```bash
kubectl get svc nginx-ingress -n nginx-ingress
```

Validate HTTPS:

```bash
curl -k \
  --resolve "secure-app.local:<HTTPS-NODEPORT>:<NODE-IP>" \
  "https://secure-app.local:<HTTPS-NODEPORT>/"
```

Validate HTTP-to-HTTPS behavior:

```bash
curl -I \
  --resolve "secure-app.local:<HTTP-NODEPORT>:<NODE-IP>" \
  "http://secure-app.local:<HTTP-NODEPORT>/"
```

### 12. Validate the Certificate Presented by Ingress

```bash
echo | openssl s_client \
  -connect "<NODE-IP>:<HTTPS-NODEPORT>" \
  -servername secure-app.local \
  2>/dev/null \
  | openssl x509 \
      -noout \
      -subject \
      -issuer \
      -dates \
      -fingerprint \
      -sha256 \
      -ext subjectAltName
```

### 13. Validate Network Isolation

Allowed frontend-to-backend communication:

```bash
kubectl run frontend-validation \
  --image=busybox:1.36 \
  --restart=Never \
  -n frontend \
  --command -- sh -c \
  'wget -T 5 -qO- http://api-backend.backend.svc.cluster.local'
```

Allowed backend-to-database communication:

```bash
kubectl run backend-validation \
  --image=busybox:1.36 \
  --restart=Never \
  -n backend \
  --command -- sh -c \
  'nc -zvw5 db-server.database.svc.cluster.local 5432'
```

Frontend-to-database connectivity must fail:

```bash
kubectl run segmentation-validation \
  --image=busybox:1.36 \
  --restart=Never \
  -n frontend \
  --command -- sh -c \
  'nc -zvw5 db-server.database.svc.cluster.local 5432'
```

Traffic from an untrusted namespace to the backend and database must also fail.

## Tools Used

- Kubernetes
- K3s
- kubectl
- Kubernetes NetworkPolicy
- Kubernetes Ingress
- Kubernetes Services
- Kubernetes Secrets
- NGINX Ingress Controller
- NGINX
- Apache HTTP Server
- PostgreSQL
- BusyBox
- OpenSSL
- TLS
- DNS
- Linux networking utilities
- Git

## Key Skills Demonstrated

- Designed least-privilege east-west Kubernetes networking between independently isolated application tiers.
- Implemented namespace-aware ingress and egress controls using Kubernetes NetworkPolicy.
- Validated security controls through explicit positive and negative connectivity testing.
- Configured secure north-south routing through an NGINX Ingress Controller.
- Implemented TLS termination with a SAN-enabled X.509 certificate.
- Enforced HTTP-to-HTTPS routing behavior at the ingress layer.
- Restricted DNS egress to the Kubernetes system namespace over TCP and UDP port 53.
- Diagnosed missing Kubernetes control-plane infrastructure and bootstrapped a functional cluster.
- Replaced unsafe or outdated assumptions with reproducible infrastructure configuration.
- Verified certificate presentation, workload health, ingress behavior, and traffic segmentation independently.

## Real-World Use Case

This architecture fits multi-tier enterprise platforms where frontend services, internal APIs, and databases must operate under explicit network trust boundaries. A compromised frontend workload cannot directly reach protected database services because Kubernetes NetworkPolicies constrain lateral movement at the network layer. Backend services retain only the connectivity required to perform their application responsibilities, while NGINX provides a controlled external entry point with TLS termination. The same model can be extended to payment platforms, internal APIs, regulated workloads, SaaS environments, and zero-trust Kubernetes architectures.

## Lessons Learned

- Kubernetes accepting a NetworkPolicy resource does not guarantee enforcement; the cluster networking implementation must support NetworkPolicy semantics.
- Establishing baseline connectivity before applying security controls makes policy enforcement objectively testable.
- DNS must be considered when restricting pod egress because otherwise legitimate service-name resolution can fail even when destination traffic is allowed.
- TLS certificates should contain Subject Alternative Names rather than relying solely on the legacy Common Name field.
- Ingress annotations are controller-specific and should never be copied between unrelated NGINX controller implementations without validation.
- Negative-path testing is as important as proving authorized connectivity because successful denial confirms that security boundaries are actually enforced.

## Troubleshooting Log

### Kubernetes Client Installed Without a Cluster

The environment contained `kubectl` but had no configured Kubernetes context, kubeconfig, API server, or usable control plane.

Resolution:

- Confirmed that no existing kubeconfig was available.
- Bootstrapped a lightweight K3s cluster.
- Disabled bundled Traefik to prevent ingress-controller overlap.
- Configured the user kubeconfig from `/etc/rancher/k3s/k3s.yaml`.
- Verified API readiness and node readiness before creating workloads.

### PostgreSQL Initialization Failure Risk

The initial PostgreSQL configuration used the official container without supplying initialization credentials.

Resolution:

- Added explicit PostgreSQL initialization environment configuration.
- Validated successful Deployment rollout before performing networking tests.

For production use, credentials should be managed through Kubernetes Secrets or an external secrets platform.

### NetworkPolicy DNS Handling

A broad DNS rule would unnecessarily permit port 53 traffic to arbitrary destinations, while UDP-only DNS could break TCP fallback behavior.

Resolution:

- Restricted DNS traffic to the `kube-system` namespace.
- Permitted both UDP/53 and TCP/53.
- Retained deny-by-default behavior for unrelated egress destinations.

### Ingress Controller Assumption

The environment did not contain the expected preconfigured ingress controller.

Resolution:

- Installed a dedicated NGINX Ingress Controller.
- Disabled K3s Traefik to avoid conflicting ingress implementations.
- Exposed the NGINX controller through NodePort services.
- Explicitly bound the application Ingress to the `nginx` IngressClass.

### Controller-Specific Annotation Compatibility

Ingress annotations from one NGINX implementation are not automatically compatible with another controller.

Resolution:

- Used the annotation model supported by the deployed NGINX controller.
- Explicitly configured HTTP-to-HTTPS redirection.
- Verified redirect behavior using live HTTP requests.

### Legacy TLS Certificate Structure

A certificate containing only a Common Name does not meet modern hostname-validation expectations.

Resolution:

- Created an OpenSSL configuration containing `subjectAltName`.
- Generated the certificate with `DNS:secure-app.local`.
- Verified both the generated certificate and the certificate actually presented through the ingress endpoint.

### Security Validation

Security controls were validated from both directions:

```text
Authorized Path              Result
---------------------------  -------
frontend -> backend          ALLOWED
backend -> database          ALLOWED

Unauthorized Path            Result
---------------------------  -------
frontend -> database         BLOCKED
untrusted -> backend         BLOCKED
untrusted -> database        BLOCKED
```

This verifies that required application communication remains operational while unauthorized lateral movement is denied.
