# Cloud-Native Security Defense in Depth

## What This Does

This implementation demonstrates layered security controls for containerized workloads running on Kubernetes. It combines workload isolation, namespace-scoped RBAC, network restrictions, hardened container execution, vulnerability scanning, admission-time policy enforcement, and automated compliance validation.

The environment demonstrates how multiple cloud-native security controls work together rather than relying on a single defensive mechanism. Vulnerable and hardened container images are compared with Trivy, Kubernetes permissions are validated through service-account impersonation, and insecure workloads are actively rejected through native Kubernetes admission policies.

The result is a reproducible security baseline that demonstrates practical defense-in-depth across container, workload, and Kubernetes cluster layers.

## Architecture

    +------------------------------------------------------------------+
    |                   CLOUD-NATIVE SECURITY STACK                     |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                         CODE / IMAGE LAYER                        |
    |                                                                  |
    |  OWASP NodeGoat                                                  |
    |       |                                                          |
    |       +--> Vulnerable Image                                      |
    |       |         |                                                |
    |       |         +--> Trivy HIGH / CRITICAL Scan                  |
    |       |                                                          |
    |       +--> Hardened Image                                        |
    |                 |                                                |
    |                 +--> Current Node.js Runtime                     |
    |                 +--> Non-Root Execution                          |
    |                 +--> Reduced Attack Surface                      |
    |                 +--> Trivy Comparison                            |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                       KUBERNETES CLUSTER                          |
    |                                                                  |
    |  +----------------+   +----------------+   +------------------+   |
    |  | development    |   | production     |   | security         |   |
    |  |                |   |                |   |                  |   |
    |  | dev-user       |   | prod-reader    |   | security tooling |   |
    |  | dev-role       |   | read-only role |   |                  |   |
    |  +-------+--------+   +-------+--------+   +------------------+   |
    |          |                    |                                  |
    |          +--------- RBAC -----+                                  |
    |                                                                  |
    |  NetworkPolicy                                                   |
    |       |                                                          |
    |       +--> Namespace Traffic Isolation                           |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                       WORKLOAD SECURITY                           |
    |                                                                  |
    |  secure-app                                                      |
    |     |                                                            |
    |     +--> runAsNonRoot                                            |
    |     +--> readOnlyRootFilesystem                                  |
    |     +--> allowPrivilegeEscalation: false                         |
    |     +--> Drop ALL Linux Capabilities                             |
    |     +--> RuntimeDefault Seccomp                                  |
    |     +--> CPU / Memory Requests and Limits                        |
    |     +--> Service Account Token Automount Disabled                |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                       ADMISSION CONTROL                           |
    |                                                                  |
    |  ValidatingAdmissionPolicy                                       |
    |     |                                                            |
    |     +--> Reject :latest Images                                   |
    |     +--> Require runAsNonRoot                                    |
    |     +--> Require Privilege Escalation Disabled                   |
    |                                                                  |
    |  Insecure Pod  ---> DENIED                                       |
    |  Compliant Pod ---> ALLOWED                                      |
    +------------------------------------------------------------------+
                                  |
                                  v
    +------------------------------------------------------------------+
    |                     SECURITY VALIDATION                           |
    |                                                                  |
    |  Trivy Image Scanning                                            |
    |  Automated Vulnerability Gate                                    |
    |  RBAC Permission Validation                                      |
    |  Admission Enforcement Testing                                   |
    |  Security Monitoring                                             |
    |  Kubernetes Compliance Scanner                                   |
    +------------------------------------------------------------------+

## Prerequisites

The following components are required:

- Ubuntu or another Linux distribution
- Docker Engine
- Kubernetes cluster
- kubectl
- Minikube or another compatible Kubernetes environment
- Trivy
- Git
- jq
- curl
- Bash
- Internet access for container images and vulnerability databases

Recommended local resources:

- 2 CPU cores or more
- 3 GB RAM or more
- At least 10 GB available storage

## Setup & Installation

Install the required system utilities:

    sudo apt-get update
    sudo apt-get install -y wget gnupg ca-certificates jq git curl

Install Minikube:

    curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm -f minikube-linux-amd64

Install Trivy:

    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
      | gpg --dearmor \
      | sudo tee /usr/share/keyrings/trivy.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
      | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null

    sudo apt-get update
    sudo apt-get install -y trivy

Enable Docker access:

    sudo usermod -aG docker "$USER"

Start the Kubernetes environment:

    minikube start --driver=docker --cpus=2 --memory=2800mb

Verify cluster connectivity:

    kubectl cluster-info
    kubectl get nodes -o wide
    kubectl config current-context

## How to Reproduce

### 1. Create Security Namespaces

Create isolated Kubernetes namespaces:

    kubectl create namespace development
    kubectl create namespace production
    kubectl create namespace security
    kubectl create namespace monitoring

Apply organizational labels:

    kubectl label namespace development environment=dev
    kubectl label namespace production environment=prod
    kubectl label namespace security purpose=security-tools

Verify:

    kubectl get namespaces --show-labels

### 2. Apply Network Isolation

Apply the development namespace NetworkPolicy:

    kubectl apply -f dev-network-policy.yaml

Verify:

    kubectl get networkpolicy -n development
    kubectl describe networkpolicy dev-isolation -n development

The policy restricts ingress and egress traffic for workloads in the development namespace according to namespace-based rules.

NetworkPolicy enforcement depends on the Kubernetes CNI implementation supporting policy enforcement.

### 3. Configure Namespace-Scoped RBAC

Create the required service accounts:

    kubectl create serviceaccount dev-user -n development
    kubectl create serviceaccount prod-reader -n production

Apply custom roles:

    kubectl apply -f dev-role.yaml
    kubectl apply -f prod-reader-role.yaml

Apply RoleBindings:

    kubectl apply -f dev-rolebinding.yaml
    kubectl apply -f prod-reader-rolebinding.yaml

Verify resources:

    kubectl get roles,rolebindings -n development
    kubectl get roles,rolebindings -n production

### 4. Validate RBAC Permissions

Verify development write access:

    kubectl auth can-i create pods \
      --as=system:serviceaccount:development:dev-user \
      -n development

Expected result:

    yes

Verify the same identity cannot create production workloads:

    kubectl auth can-i create pods \
      --as=system:serviceaccount:development:dev-user \
      -n production

Expected result:

    no

Verify production read access:

    kubectl auth can-i get pods \
      --as=system:serviceaccount:production:prod-reader \
      -n production

Expected result:

    yes

Verify production write access is denied:

    kubectl auth can-i create pods \
      --as=system:serviceaccount:production:prod-reader \
      -n production

Expected result:

    no

### 5. Deploy the Hardened Kubernetes Workload

Apply the hardened application:

    kubectl apply -f secure-app-deployment.yaml

Wait for deployment:

    kubectl rollout status deployment/secure-app \
      -n development \
      --timeout=120s

Verify:

    kubectl get deployments -n development
    kubectl get pods -n development -o wide

The workload applies several runtime controls:

- Non-root execution
- Disabled privilege escalation
- Read-only root filesystem
- Dropped Linux capabilities
- RuntimeDefault seccomp profile
- Explicit CPU requests and limits
- Explicit memory requests and limits
- Disabled automatic service-account token mounting

### 6. Establish the Vulnerable Container Baseline

The intentionally vulnerable image provides a comparison point for vulnerability analysis.

Build the image:

    sudo docker build -t nodegoat:vulnerable .

Scan it:

    sudo trivy image nodegoat:vulnerable

Generate a JSON report:

    sudo trivy image \
      --format json \
      --output nodegoat-vulnerable-scan.json \
      nodegoat:vulnerable

### 7. Analyze Vulnerability Results

Count all vulnerabilities across every Trivy result section:

    jq '
    [
      .Results[]?
      | .Vulnerabilities[]?
    ]
    | length
    ' nodegoat-vulnerable-scan.json

Count HIGH and CRITICAL vulnerabilities:

    jq '
    [
      .Results[]?
      | .Vulnerabilities[]?
      | select(.Severity == "HIGH" or .Severity == "CRITICAL")
    ]
    | length
    ' nodegoat-vulnerable-scan.json

This avoids relying exclusively on the first Trivy result section and provides a more complete vulnerability count.

### 8. Build the Hardened Container Image

Build the improved image:

    sudo docker build \
      -f Dockerfile.secure \
      -t nodegoat:secure \
      .

Verify the configured user:

    sudo docker inspect nodegoat:secure \
      --format 'Configured user: {{.Config.User}}'

The image uses:

- Current Node.js runtime
- Non-root execution
- Production-only dependency installation
- Reduced development artifacts
- Controlled application ownership
- Smaller Alpine-based runtime

### 9. Scan the Hardened Image

Generate a second vulnerability report:

    sudo trivy image \
      --format json \
      --output nodegoat-secure-scan.json \
      nodegoat:secure

Review HIGH and CRITICAL vulnerabilities:

    jq '
    [
      .Results[]?
      | .Vulnerabilities[]?
      | select(.Severity == "HIGH" or .Severity == "CRITICAL")
    ]
    | length
    ' nodegoat-secure-scan.json

The two reports provide measurable before-and-after security evidence.

### 10. Run Automated Image Security Checks

Enable execution:

    chmod +x scan-images.sh

Run:

    ./scan-images.sh

The script scans multiple images for HIGH and CRITICAL vulnerabilities.

Its exit status can be consumed by CI/CD systems to prevent vulnerable images from progressing through a deployment pipeline.

### 11. Enable Kubernetes Admission Enforcement

Apply the native Kubernetes admission policy:

    kubectl apply -f image-security-policy.yaml

Verify:

    kubectl get validatingadmissionpolicy
    kubectl get validatingadmissionpolicybinding

The policy rejects workloads that:

- Use the :latest image tag
- Do not explicitly require non-root execution
- Allow privilege escalation

### 12. Prove Admission Enforcement

Attempt to deploy the intentionally insecure pod:

    kubectl apply -f insecure-test-pod.yaml

Expected result:

    ValidatingAdmissionPolicy denied request:
    Images using the :latest tag are not permitted.

Deploy the compliant workload:

    kubectl apply -f secure-test-pod.yaml

Verify:

    kubectl get pod secure-policy-test \
      -n development

Clean up:

    kubectl delete pod secure-policy-test \
      -n development

This proves that admission controls are actively enforcing security policy rather than simply existing as configuration objects.

### 13. Deploy Security Monitoring

Apply the monitoring workload:

    kubectl apply -f security-monitor.yaml

Verify rollout:

    kubectl rollout status deployment/security-monitor \
      -n monitoring

View monitoring logs:

    kubectl logs \
      -n monitoring \
      deployment/security-monitor \
      --tail=10

The monitoring workload itself follows hardened runtime practices including non-root execution, dropped capabilities, read-only filesystem access, seccomp, and resource restrictions.

### 14. Run Kubernetes Security Compliance Validation

Enable the scanner:

    chmod +x security-compliance-check.sh

Run:

    ./security-compliance-check.sh

The scanner validates:

- Anonymous RBAC exposure
- Explicit non-root workload configuration
- NetworkPolicy availability
- Default service-account usage
- CPU and memory limits
- Privilege escalation controls
- ValidatingAdmissionPolicy availability
- Admission policy binding availability

### 15. Inspect the Final Security State

Review development workloads:

    kubectl get pods -n development -o wide

Review monitoring workloads:

    kubectl get pods -n monitoring -o wide

Review NetworkPolicies:

    kubectl get networkpolicies --all-namespaces

Review RBAC:

    kubectl get roles,rolebindings -n development
    kubectl get roles,rolebindings -n production

Review admission policies:

    kubectl get validatingadmissionpolicy
    kubectl get validatingadmissionpolicybinding

## Security Controls Implemented

### Container Security

- Vulnerability scanning with Trivy
- Vulnerable versus hardened image comparison
- Production-only dependency installation
- Non-root container execution
- Reduced container attack surface
- Automated vulnerability gating

### Kubernetes Workload Security

- Non-root execution
- Read-only root filesystem
- Disabled privilege escalation
- Dropped Linux capabilities
- RuntimeDefault seccomp
- CPU and memory limits
- Disabled unnecessary service-account token mounting

### Identity and Access Management

- Dedicated Kubernetes service accounts
- Namespace-scoped Roles
- Namespace-scoped RoleBindings
- Development write permissions
- Production read-only permissions
- Cross-namespace access validation

### Network Security

- Kubernetes NetworkPolicy
- Namespace-based traffic restrictions
- Development environment isolation

### Admission Security

- Kubernetes ValidatingAdmissionPolicy
- ValidatingAdmissionPolicyBinding
- Prevention of :latest image usage
- Mandatory non-root workload configuration
- Mandatory privilege escalation restrictions

### Security Automation

- Trivy JSON reporting
- Automated vulnerability scanning
- CI-compatible security gate
- Kubernetes compliance scanner
- Admission enforcement validation

## Tools Used

- Kubernetes
- kubectl
- Minikube
- Docker
- Trivy
- Kubernetes RBAC
- Kubernetes NetworkPolicy
- ValidatingAdmissionPolicy
- ValidatingAdmissionPolicyBinding
- Linux SecurityContext
- Seccomp
- Linux capabilities
- Bash
- jq
- Git
- curl
- OWASP NodeGoat

## Key Skills Demonstrated

- Kubernetes security engineering
- Cloud-native defense in depth
- Container image hardening
- Container vulnerability management
- Kubernetes workload hardening
- Least-privilege RBAC design
- Service-account security
- Namespace-based workload isolation
- Kubernetes NetworkPolicy configuration
- Linux capability restriction
- Seccomp enforcement
- Read-only filesystem configuration
- Resource governance
- Kubernetes admission control
- Policy-as-code principles
- Security automation
- Vulnerability gating
- Compliance validation
- Security troubleshooting
- CI/CD security control design

## Real-World Use Case

A platform engineering or DevSecOps team can apply this security model to a shared Kubernetes environment where multiple development teams deploy workloads independently.

Namespace-scoped RBAC limits each identity to the resources it requires. NetworkPolicies reduce lateral movement between workloads. SecurityContext controls restrict container privileges at runtime. Trivy identifies known vulnerabilities before deployment, while admission policies prevent workloads that violate defined security requirements from entering the cluster.

Automated compliance checks provide an additional validation layer for identifying missing controls or configuration drift.

Together, these controls create a practical Kubernetes security baseline suitable for internal development platforms, CI/CD pipelines, microservice environments, and cloud-native application platforms.

## Lessons Learned

- Creating a Kubernetes security resource does not necessarily prove the underlying control is actively enforced. Security mechanisms should be tested behaviorally.

- Vulnerability analysis should aggregate all Trivy result sections instead of assuming the first result contains every vulnerability.

- Container security requires both image-level hardening and Kubernetes runtime restrictions.

- Non-root execution alone is insufficient; privilege escalation, filesystem permissions, Linux capabilities, and seccomp should also be controlled.

- Namespace-scoped RBAC provides stronger isolation than broad cluster-level permissions.

- Service accounts should receive only the permissions required by their workloads.

- Admission policies become meaningful only after being bound and tested with both compliant and non-compliant workloads.

- Security automation should return useful exit codes so it can later integrate with CI/CD pipelines.

- Control-plane workloads and application workloads may require different compliance baselines and should not always be assessed identically.

## Troubleshooting Log

### Minikube Was Missing

The Kubernetes client was installed, but Minikube was unavailable and no cluster context existed.

Resolution:

    curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube

The cluster was then initialized with:

    minikube start --driver=docker --cpus=2 --memory=2800mb

### Trivy Was Missing

Trivy was not installed in the environment.

Resolution:

The official Trivy repository was configured and the package installed through APT.

### Kubernetes Cluster Was Initially Unreachable

kubectl existed but did not have an active Kubernetes context.

Resolution:

Starting Minikube created the local cluster and configured kubectl automatically.

### Vulnerable Container Runtime Was Outdated

The intentionally vulnerable image used an obsolete Node.js runtime.

Resolution:

The outdated runtime was retained only as the vulnerable comparison baseline.

The hardened image was rebuilt using a current Node.js runtime.

### Trivy Vulnerability Counting Was Incomplete

Querying:

    .Results[0].Vulnerabilities

only examines one result section.

Resolution:

The analysis was changed to aggregate:

    .Results[]?.Vulnerabilities[]?

This captures vulnerabilities from all available result sections.

### Hardened Nginx Workload Could Fail Under Restricted Permissions

A standard nginx image normally expects filesystem locations and ports that can conflict with strict non-root security configuration.

Resolution:

An unprivileged nginx image was used together with:

- Non-root execution
- Port 8080
- Read-only root filesystem
- Writable temporary volumes
- Dropped capabilities
- RuntimeDefault seccomp

### Service Account Tokens Were Unnecessarily Mounted

Application workloads do not automatically require access to the Kubernetes API.

Resolution:

Automatic service-account token mounting was explicitly disabled where unnecessary.

### Original Admission Policy Was Not Enforceable

A ConfigMap containing Rego text does not enforce Kubernetes admission decisions unless a policy engine such as OPA Gatekeeper consumes it.

Resolution:

Native Kubernetes ValidatingAdmissionPolicy and ValidatingAdmissionPolicyBinding resources were implemented instead.

### Invalid SecurityContext Field

The original policy logic referenced:

    runAsRoot

This is not a valid Kubernetes security context field.

Resolution:

Admission validation was implemented using supported Kubernetes controls:

    runAsNonRoot
    allowPrivilegeEscalation

### Admission Enforcement Required Behavioral Testing

Simply creating an admission policy does not prove enforcement.

Resolution:

An intentionally insecure workload using:

    nginx:latest

was submitted to the Kubernetes API.

The API server rejected it with:

    Images using the :latest tag are not permitted.

A compliant workload was subsequently accepted.

### Root Container Detection Could Miss Container-Level Settings

Checking only pod-level securityContext values can miss security settings defined directly on individual containers.

Resolution:

The compliance scanner evaluates Kubernetes JSON with jq and inspects container-level configuration.

### Resource Limit Detection Could Produce False Results

Simple grep-based parsing of kubectl output is unreliable for nested resource definitions.

Resolution:

CPU and memory limits are evaluated directly from structured Kubernetes JSON.

## Outcome

This implementation establishes a multi-layer Kubernetes security baseline combining preventive, detective, and validation controls.

The final environment demonstrates:

- Identity isolation through RBAC
- Network isolation through NetworkPolicy
- Hardened Kubernetes workloads
- Container vulnerability management
- Admission-time security enforcement
- Automated security validation
- Repeatable compliance assessment

These controls represent core capabilities used by DevSecOps, platform engineering, Kubernetes security, AIOps, and cloud-native infrastructure teams.
