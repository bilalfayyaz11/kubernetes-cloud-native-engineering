# Kubernetes RBAC and Workload Identity Security

## What This Does

This implementation establishes least-privilege identity and authorization controls for users and workloads inside Kubernetes. Namespace-scoped Roles and RoleBindings restrict a certificate-authenticated developer identity to read-only Pod operations while a dedicated Service Account receives only the API permissions required by its workload. Resource-specific Secret access prevents the workload from reading unrelated credentials, and cross-namespace authorization remains denied. The resulting model demonstrates practical separation of duties between human and workload identities.

## Architecture

```text
                         Kubernetes API Server
                                  |
                    +-------------+-------------+
                    |                           |
                    |                           |
          Human Identity                 Workload Identity
                    |                           |
                    v                           v
          +------------------+        +----------------------+
          | developer        |        | app-service-account  |
          | X.509 client cert|        | Service Account      |
          +---------+--------+        +----------+-----------+
                    |                            |
                    | RoleBinding                | RoleBinding
                    v                            v
          +------------------+        +----------------------+
          | pod-reader       |        | app-minimal-role     |
          | Role             |        | Role                 |
          +---------+--------+        +----------+-----------+
                    |                            |
                    |                            |
        +-----------+------------+      +--------+----------------+
        |                        |      |                         |
        v                        v      v                         v
   Pod metadata              Pod logs  ConfigMaps              app-secret
   get/list/watch               get    get/list                   get
        |                        |      |                         |
        +------------------------+      +-------------------------+
                    |
                    |
             secure-app namespace
                    |
       +------------+-------------+
       |                          |
       v                          v
 restricted-secret           default namespace
      DENIED                     DENIED
```

## Security Model

```text
IDENTITY                  ACTION / RESOURCE                         RESULT
------------------------  ----------------------------------------  -------
developer                 Get Pods in secure-app                    ALLOW
developer                 List Pods in secure-app                   ALLOW
developer                 Watch Pods in secure-app                  ALLOW
developer                 Read Pod logs in secure-app               ALLOW
developer                 Create Pods                               DENY
developer                 Delete Pods                               DENY
developer                 Read Secrets                              DENY
developer                 Access Pods in default namespace          DENY

app-service-account       Get app-config                            ALLOW
app-service-account       List ConfigMaps                           ALLOW
app-service-account       Get app-secret                            ALLOW
app-service-account       Get restricted-secret                     DENY
app-service-account       List Secrets                              DENY
app-service-account       Create or delete Pods                     DENY
app-service-account       Access Pods in default namespace          DENY

default Service Account   List Pods in secure-app                   DENY
```

## Prerequisites

- Linux host with administrative sudo access
- Kubernetes cluster
- `kubectl`
- OpenSSL
- GNU coreutils
- Git
- RBAC authorization enabled
- Kubernetes CertificateSigningRequest API
- Permissions to create namespaces, Roles, RoleBindings, Service Accounts, Pods, ConfigMaps, Secrets, and CertificateSigningRequests

A lightweight K3s cluster is sufficient for reproducing this configuration.

## Setup & Installation

### Bootstrap Kubernetes When No Cluster Exists

```bash
curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh

sudo sh /tmp/install-k3s.sh \
  --write-kubeconfig-mode=644

mkdir -p "$HOME/.kube"

sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

export KUBECONFIG="$HOME/.kube/config"

kubectl get nodes -o wide
kubectl auth can-i '*' '*' --all-namespaces
```

Verify the required APIs:

```bash
kubectl api-resources \
  | grep -E 'roles|rolebindings|clusterroles|clusterrolebindings'

kubectl api-resources \
  | grep -i certificatesigningrequest

kubectl api-resources \
  | grep -i '^serviceaccounts'
```

## How to Reproduce

### 1. Create the Security Namespace

```bash
kubectl create namespace secure-app
```

### 2. Create the Developer Pod Reader Role

Apply:

```bash
kubectl apply -f pod-reader-role.yaml
```

The Role permits:

```text
pods:
  get
  list
  watch

pods/log:
  get
```

It does not grant Pod creation, deletion, Secret access, or cluster-wide permissions.

### 3. Create a Certificate-Based Developer Identity

Generate the private key locally:

```bash
openssl genrsa \
  -out developer.key \
  2048

chmod 600 developer.key
```

Create the CSR:

```bash
openssl req \
  -new \
  -key developer.key \
  -out developer.csr \
  -subj "/CN=developer/O=development"
```

Encode it for Kubernetes:

```bash
CSR_DATA="$(base64 -w 0 developer.csr)"
```

Create the CertificateSigningRequest dynamically:

```bash
cat > /tmp/developer-csr.yaml <<EOF_CSR
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: developer-csr
spec:
  request: ${CSR_DATA}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF_CSR

kubectl apply -f /tmp/developer-csr.yaml
kubectl certificate approve developer-csr
```

Extract the signed client certificate:

```bash
kubectl get csr developer-csr \
  -o jsonpath='{.status.certificate}' \
  | base64 -d \
  > developer.crt
```

Verify the certificate:

```bash
openssl x509 \
  -in developer.crt \
  -noout \
  -subject \
  -issuer \
  -dates
```

Private keys and generated identity certificates are intentionally excluded from source control.

### 4. Bind the Developer Identity

```bash
kubectl apply -f pod-reader-binding.yaml
```

Verify the authorization boundary:

```bash
kubectl auth can-i get pods \
  --as=developer \
  -n secure-app

kubectl auth can-i list pods \
  --as=developer \
  -n secure-app

kubectl auth can-i get pods/log \
  --as=developer \
  -n secure-app

kubectl auth can-i create pods \
  --as=developer \
  -n secure-app

kubectl auth can-i get secrets \
  --as=developer \
  -n secure-app
```

Expected result:

```text
get pods       yes
list pods      yes
get pods/log   yes
create pods    no
get secrets    no
```

### 5. Create the Workload Service Account

```bash
kubectl create serviceaccount \
  app-service-account \
  -n secure-app
```

Apply its least-privilege Role and RoleBinding:

```bash
kubectl apply -f app-minimal-role.yaml
kubectl apply -f app-service-binding.yaml
```

### 6. Create Authorization Test Resources

Create the application ConfigMap:

```bash
kubectl create configmap app-config \
  --from-literal=database_url=localhost:5432 \
  -n secure-app
```

Generate non-production test values without storing them in Git:

```bash
APP_API_KEY="$(openssl rand -hex 24)"
RESTRICTED_VALUE="$(openssl rand -hex 24)"
```

Create the Secret the Service Account is explicitly authorized to read:

```bash
kubectl create secret generic app-secret \
  --from-literal=api_key="$APP_API_KEY" \
  -n secure-app
```

Create a second Secret that must remain inaccessible:

```bash
kubectl create secret generic restricted-secret \
  --from-literal=admin_password="$RESTRICTED_VALUE" \
  -n secure-app
```

The Role references only `app-secret` through `resourceNames`, so access to `restricted-secret` remains denied.

### 7. Deploy Service Account Test Pods

```bash
kubectl apply -f default-sa-pod.yaml
kubectl apply -f custom-sa-pod.yaml

kubectl wait \
  --for=condition=Ready \
  pod/default-sa-pod \
  -n secure-app \
  --timeout=120s

kubectl wait \
  --for=condition=Ready \
  pod/custom-sa-pod \
  -n secure-app \
  --timeout=120s
```

The Pods use a purpose-built curl container so API testing does not depend on installing packages into a running application container.

### 8. Verify Service Account Assignment

```bash
kubectl get pod default-sa-pod \
  -n secure-app \
  -o jsonpath='{.spec.serviceAccountName}{"\n"}'

kubectl get pod custom-sa-pod \
  -n secure-app \
  -o jsonpath='{.spec.serviceAccountName}{"\n"}'
```

Expected identities:

```text
default-sa-pod -> default
custom-sa-pod  -> app-service-account
```

### 9. Test the Default Service Account

Execute inside the default identity Pod:

```bash
kubectl exec default-sa-pod -n secure-app -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  --cacert "$CACERT" \
  https://kubernetes.default.svc/api/v1/namespaces/secure-app/pods
'
```

Expected result:

```text
403
```

The default Service Account receives no implicit workload privileges.

### 10. Test Authorized ConfigMap Access

```bash
kubectl exec custom-sa-pod -n secure-app -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  --cacert "$CACERT" \
  https://kubernetes.default.svc/api/v1/namespaces/secure-app/configmaps/app-config
'
```

Expected result:

```text
200
```

### 11. Test Authorized Secret Access

```bash
kubectl exec custom-sa-pod -n secure-app -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  --cacert "$CACERT" \
  https://kubernetes.default.svc/api/v1/namespaces/secure-app/secrets/app-secret
'
```

Expected result:

```text
200
```

### 12. Prove Restricted Secret Access Is Denied

```bash
kubectl exec custom-sa-pod -n secure-app -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  --cacert "$CACERT" \
  https://kubernetes.default.svc/api/v1/namespaces/secure-app/secrets/restricted-secret
'
```

Expected result:

```text
403
```

### 13. Prove Secret Enumeration Is Denied

```bash
kubectl exec custom-sa-pod -n secure-app -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  --cacert "$CACERT" \
  https://kubernetes.default.svc/api/v1/namespaces/secure-app/secrets
'
```

Expected result:

```text
403
```

### 14. Prove Cross-Namespace Access Is Denied

```bash
kubectl exec custom-sa-pod -n secure-app -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  --cacert "$CACERT" \
  https://kubernetes.default.svc/api/v1/namespaces/default/pods
'
```

Expected result:

```text
403
```

### 15. Audit Authorization with kubectl

```bash
SA_USER="system:serviceaccount:secure-app:app-service-account"

kubectl auth can-i --list \
  --as="$SA_USER" \
  -n secure-app

kubectl auth can-i get configmap/app-config \
  --as="$SA_USER" \
  -n secure-app

kubectl auth can-i get secret/app-secret \
  --as="$SA_USER" \
  -n secure-app

kubectl auth can-i get secret/restricted-secret \
  --as="$SA_USER" \
  -n secure-app

kubectl auth can-i list secrets \
  --as="$SA_USER" \
  -n secure-app

kubectl auth can-i delete pods \
  --as="$SA_USER" \
  -n secure-app
```

## Tools Used

- Kubernetes
- K3s
- kubectl
- Kubernetes RBAC
- Roles
- RoleBindings
- Service Accounts
- CertificateSigningRequests
- X.509 client certificates
- OpenSSL
- Kubernetes API
- Projected Service Account tokens
- curl
- YAML
- Linux
- Git

## Key Skills Demonstrated

- Designed namespace-scoped Kubernetes authorization using least-privilege RBAC.
- Separated human and workload identities using X.509 certificates and Service Accounts.
- Restricted Secret access to a single explicitly authorized resource.
- Prevented Secret enumeration through resource-level RBAC constraints.
- Validated authorization behavior directly against the Kubernetes API.
- Tested both positive and negative security paths using deterministic HTTP status codes.
- Verified namespace isolation at the authorization layer.
- Audited effective permissions using `kubectl auth can-i`.
- Eliminated unnecessary privileges from the default Service Account.
- Validated workload identity through projected Service Account credentials.

## Real-World Use Case

Enterprise Kubernetes environments frequently contain multiple teams, applications, and automation identities sharing the same cluster. Developers may require visibility into workload health without receiving deployment or Secret-management privileges, while application workloads may need access to one configuration object or credential without being able to enumerate other sensitive resources. Namespace-scoped Roles and resource-specific authorization rules provide these boundaries while retaining centralized Kubernetes API governance. This pattern is directly applicable to regulated platforms, multi-tenant clusters, CI/CD workloads, internal developer platforms, and production application environments.

## Lessons Learned

- Kubernetes identities should receive only the verbs and resources required for their responsibilities.
- Human and workload authorization should be modeled separately rather than sharing privileged credentials.
- `resourceNames` can significantly reduce Secret exposure by limiting access to explicitly named objects.
- A successful API request is only half of authorization testing; denied operations must also be validated.
- Namespace-scoped Roles provide a safer default than ClusterRoles when cluster-wide privileges are unnecessary.
- Modern Service Account authentication uses projected credentials mounted into Pods rather than relying on permanently created token Secrets.
- `kubectl auth can-i` provides a fast way to audit effective authorization before troubleshooting application-level API failures.

## Troubleshooting Log

### Kubernetes Client Present Without a Cluster

The environment contained `kubectl` but no active context, kubeconfig, API server, or Kubernetes control plane.

Resolution:

- Confirmed cluster access was unavailable.
- Bootstrapped a lightweight K3s control plane.
- Configured the user kubeconfig.
- Verified node readiness and RBAC APIs before creating authorization resources.

### Over-Permissive Pod Log Rule

The initial Pod log rule included an unnecessary `list` verb for the `pods/log` subresource.

Resolution:

- Reduced the rule to the `get` verb required for reading Pod logs.

### Mutable API Test Containers

Installing curl interactively inside an application container creates unnecessary package-manager dependencies and reduces reproducibility.

Resolution:

- Replaced mutable nginx-based test containers with a purpose-built curl container image.
- API validation now runs without changing the container after startup.

### Service Account Credential Handling

Modern Kubernetes workloads receive projected Service Account credentials inside Pods.

Resolution:

- Used the mounted token and cluster CA from:

```text
/var/run/secrets/kubernetes.io/serviceaccount/
```

- Authenticated directly to `https://kubernetes.default.svc`.
- Validated responses using HTTP status codes.

### Secret Access Granularity

Granting general Secret read permission would expose unrelated application credentials.

Resolution:

- Limited the Service Account to `get` on the explicitly named `app-secret`.
- Confirmed access to `restricted-secret` returns `403`.
- Confirmed Secret enumeration also returns `403`.

### Cross-Namespace Authorization

A workload identity should not automatically gain permissions outside the namespace containing its RoleBinding.

Resolution:

- Bound the Service Account only inside `secure-app`.
- Verified attempts to access Pods in `default` are denied.

## Security Validation Summary

```text
Developer Identity
------------------------------------------------
Read Pods                       PASS
List Pods                       PASS
Watch Pods                      PASS
Read Pod logs                   PASS
Create Pods                     DENIED
Delete Pods                     DENIED
Read Secrets                    DENIED
Cross-namespace Pod access      DENIED

Application Service Account
------------------------------------------------
Read app-config                 PASS
List ConfigMaps                 PASS
Read app-secret                 PASS
Read restricted-secret          DENIED
List Secrets                    DENIED
Delete Pods                     DENIED
Cross-namespace Pod access      DENIED

Default Service Account
------------------------------------------------
List secure-app Pods            DENIED
```

The final state preserves required functionality while minimizing privileges for both human and workload identities.
