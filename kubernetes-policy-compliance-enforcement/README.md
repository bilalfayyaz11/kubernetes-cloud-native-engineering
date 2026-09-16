# Kubernetes Compliance Policy Enforcement

## What This Does

This implementation establishes automated Kubernetes compliance enforcement using OPA Gatekeeper. Security policies prevent workloads from running as root or using privileged containers, while continuous audit capabilities identify policy violations across the cluster.

The solution combines admission-time enforcement, reusable ConstraintTemplates, parameterized Constraints, namespace exemptions, dry-run evaluation, compliance reporting, and operational troubleshooting. The result is a policy-as-code control plane that blocks insecure workloads before they are persisted while also supporting safe rollout and governance testing.

## Architecture

```text
                  KUBERNETES COMPLIANCE CONTROL

┌─────────────────────────────────────────────────────────────┐
│                    WORKLOAD SUBMISSION                      │
│                                                             │
│    Pod / Deployment Manifest                                │
│              │                                              │
│              ▼                                              │
│      Kubernetes API Server                                  │
└──────────────┬──────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│                  GATEKEEPER ADMISSION                       │
│                                                             │
│   ConstraintTemplates                                       │
│        │                                                    │
│        ├── Require Non-Root                                 │
│        │                                                    │
│        └── Deny Privileged Containers                       │
│                                                             │
│   Constraints                                               │
│        │                                                    │
│        ├── enforcementAction: deny                          │
│        └── enforcementAction: dryrun                        │
│                                                             │
│              │                                              │
│        ┌─────┴─────┐                                        │
│        │           │                                        │
│      COMPLY     VIOLATE                                     │
│        │           │                                        │
│        ▼           ▼                                        │
│      ADMIT        DENY                                      │
└──────────────┬──────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────┐
│                    CONTINUOUS AUDIT                         │
│                                                             │
│   Gatekeeper Audit                                          │
│        │                                                    │
│        ▼                                                    │
│   Constraint Status                                         │
│        │                                                    │
│        ▼                                                    │
│   Compliance Reports                                        │
│   Troubleshooting Evidence                                  │
└─────────────────────────────────────────────────────────────┘
```

## Security Controls

The implementation enforces two primary Kubernetes workload controls:

### Non-Root Execution

Containers must:

- explicitly set `runAsNonRoot: true`
- avoid `runAsUser: 0`
- run with a non-root UID

### Privileged Container Restriction

Containers must not set:

```yaml
privileged: true
```

These controls are evaluated at admission time before Pods are created.

## Prerequisites

Required tooling:

- Ubuntu Linux
- Docker Engine
- kubectl
- kind
- Helm
- jq
- Python 3
- OpenSSL
- Git
- Internet access

Verify the environment:

```bash
docker --version
kubectl version --client
kind version
helm version
jq --version
python3 --version
```

## Kubernetes Environment

Create the local cluster:

```bash
kind create cluster \
  --name kubernetes-compliance \
  --wait 120s
```

Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

## Gatekeeper Installation

Add the official Gatekeeper Helm repository:

```bash
helm repo add gatekeeper \
  https://open-policy-agent.github.io/gatekeeper/charts

helm repo update
```

Install Gatekeeper:

```bash
helm upgrade \
  --install gatekeeper \
  gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --wait \
  --timeout 5m
```

Verify Gatekeeper:

```bash
kubectl get pods -n gatekeeper-system
kubectl get crd | grep gatekeeper
kubectl get validatingwebhookconfigurations | grep gatekeeper
```

## Policy Model

Gatekeeper separates policy logic from policy application.

### ConstraintTemplate

A `ConstraintTemplate` defines reusable Rego policy logic.

### Constraint

A `Constraint` applies that logic with:

- enforcement mode
- resource scope
- namespaces
- parameters
- exclusions

This separation allows the same policy logic to be reused across environments with different governance requirements.

## Non-Root Policy

The non-root policy requires workloads to avoid UID 0 and explicitly opt into non-root execution.

Policy files:

```text
policies/require-non-root-template.yaml
policies/require-non-root-constraint.yaml
```

Apply:

```bash
kubectl apply \
  -f policies/require-non-root-template.yaml

kubectl apply \
  -f policies/require-non-root-constraint.yaml
```

Verify:

```bash
kubectl get constrainttemplates
kubectl get k8srequirenonroot
```

## Privileged Container Policy

The privileged-container policy rejects workloads that request privileged execution.

Policy files:

```text
policies/deny-privileged-template.yaml
policies/deny-privileged-constraint.yaml
```

Apply:

```bash
kubectl apply \
  -f policies/deny-privileged-template.yaml

kubectl apply \
  -f policies/deny-privileged-constraint.yaml
```

Verify:

```bash
kubectl get k8sdeniesprivileged
```

## Non-Compliant Workload Test

A violating Pod attempts to run as root and privileged.

Expected policy violations:

```text
runAsUser: 0
privileged: true
```

Apply:

```bash
kubectl apply \
  -f tests/non-compliant-pod.yaml
```

Expected outcome:

```text
Admission denied
```

The Pod should not exist afterward:

```bash
kubectl get pod non-compliant
```

## Compliant Workload Test

A compliant Pod uses:

```yaml
runAsNonRoot: true
runAsUser: 10001
privileged: false
allowPrivilegeEscalation: false
```

and drops Linux capabilities.

Apply:

```bash
kubectl apply \
  -f tests/compliant-pod.yaml
```

Verify:

```bash
kubectl get pod compliant
```

Expected result:

```text
Running
```

## Deployment Enforcement

Gatekeeper policies target Pod resources.

A Deployment may be accepted by the API server, but when the Deployment controller creates Pods, Gatekeeper evaluates each Pod creation request.

This demonstrates an important governance distinction:

```text
Deployment object accepted
        │
        ▼
ReplicaSet attempts Pod creation
        │
        ▼
Gatekeeper evaluates Pod
        │
   ┌────┴────┐
   │         │
Compliant  Non-Compliant
   │         │
   ▼         ▼
Admitted    Denied
```

## Continuous Compliance Audit

Gatekeeper continuously audits existing Kubernetes resources against active constraints.

Check the non-root constraint:

```bash
kubectl get k8srequirenonroot \
  must-run-as-non-root \
  -o yaml
```

Check privileged-container violations:

```bash
kubectl get k8sdeniesprivileged \
  no-privileged-containers \
  -o yaml
```

Relevant fields include:

```text
status.totalViolations
status.violations
```

## Compliance Reporting

A reusable compliance script is located at:

```text
scripts/compliance-check.sh
```

Run:

```bash
./scripts/compliance-check.sh
```

The report includes:

- Gatekeeper controller status
- active ConstraintTemplates
- active Constraints
- total policy violations
- potentially non-compliant Pods
- compliant workload status

Reports are written under:

```text
reports/
```

## Namespace Exemptions

Some namespaces may require controlled exceptions.

The non-root Constraint supports excluded namespaces such as:

```text
kube-system
kube-public
kube-node-lease
gatekeeper-system
```

A temporary namespace exemption was tested using:

```text
test-exempt
```

This demonstrated that policy scope can be intentionally narrowed without disabling the control cluster-wide.

## Dry-Run Policy Mode

Gatekeeper supports:

```yaml
enforcementAction: dryrun
```

Dry-run mode allows violating resources to be admitted while recording them as policy violations.

This is useful for:

- evaluating new policies
- measuring impact before enforcement
- avoiding unexpected production disruption
- identifying remediation work
- staged governance rollouts

The implementation used a dedicated namespace so the active deny constraint would not interfere with dry-run evaluation.

## Enforcement Modes

```text
deny
```

Blocks violating workloads.

```text
dryrun
```

Allows the workload but records a violation.

This enables a governance lifecycle such as:

```text
Policy Development
       │
       ▼
Dry-Run Evaluation
       │
       ▼
Violation Analysis
       │
       ▼
Remediation
       │
       ▼
Enforcement
```

## Troubleshooting

The troubleshooting utility is located at:

```text
scripts/troubleshoot.sh
```

Run:

```bash
./scripts/troubleshoot.sh
```

It checks:

- Gatekeeper controller health
- controller logs
- validating webhook configuration
- ConstraintTemplate status
- Constraint status
- admission APIs
- Gatekeeper CRDs
- server-side validation guidance
- common policy scope issues

## Server-Side Policy Testing

Kubernetes server-side dry-run can test admission behavior without persisting a resource:

```bash
kubectl apply \
  --dry-run=server \
  -f <manifest>
```

This is useful when debugging policy logic before creating workloads.

## Project Structure

```text
.
├── README.md
├── policy-engines-comparison.md
├── policies
│   ├── deny-privileged-constraint.yaml
│   ├── deny-privileged-template.yaml
│   ├── require-non-root-constraint.yaml
│   ├── require-non-root-constraint-exempt.yaml
│   ├── require-non-root-dryrun.yaml
│   └── require-non-root-template.yaml
├── reports
│   ├── compliance-status.txt
│   ├── dryrun-constraint-status.yaml
│   ├── dryrun-violating-pod.yaml
│   ├── exempt-pod.yaml
│   ├── final-cluster-pods.txt
│   ├── final-compliance-status.txt
│   ├── final-constrainttemplates.yaml
│   ├── final-non-root-constraints.yaml
│   ├── final-privileged-constraints.yaml
│   ├── final-troubleshooting-status.txt
│   ├── gatekeeper-controller.log
│   ├── gatekeeper-helm-release.txt
│   ├── non-root-constraint-status.yaml
│   ├── privileged-constraint-status.yaml
│   └── troubleshooting-status.txt
├── scripts
│   ├── compliance-check.sh
│   └── troubleshoot.sh
└── tests
    ├── compliant-deployment.yaml
    ├── compliant-pod.yaml
    ├── dryrun-root-pod.yaml
    ├── exempt-root-pod.yaml
    ├── non-compliant-deployment.yaml
    └── non-compliant-pod.yaml
```

## Policy Engine Comparison

### OPA Gatekeeper

Strengths:

- expressive Rego policy language
- strong OPA ecosystem integration
- reusable policy logic
- admission enforcement
- continuous audit
- strong fit for complex governance

Trade-offs:

- steeper learning curve
- policy debugging requires Rego familiarity
- more abstraction than YAML-only systems

### Kyverno

Strengths:

- Kubernetes-native YAML policy model
- approachable for Kubernetes teams
- supports validation, mutation, generation, and image policies
- easier adoption for application teams

Trade-offs:

- very complex logic may be easier in Rego
- organizations already using OPA may prefer Gatekeeper consistency

## When Gatekeeper Fits Best

Gatekeeper is particularly useful when:

- compliance requirements are complex
- Rego expertise exists
- OPA is already used elsewhere
- reusable policy logic is required
- admission and audit should share a policy model

## When Kyverno Fits Best

Kyverno is often useful when:

- Kubernetes-native YAML is preferred
- teams want a lower learning curve
- mutation and resource-generation workflows are important
- application teams manage policies directly

## Tools Used

- Kubernetes
- kind
- OPA Gatekeeper
- Open Policy Agent
- Rego
- Helm
- kubectl
- jq
- Bash
- Docker
- Git

## Key Skills Demonstrated

- Kubernetes policy-as-code
- OPA Gatekeeper administration
- Rego policy development
- ConstraintTemplate design
- Constraint lifecycle management
- Kubernetes admission control
- automated compliance enforcement
- continuous compliance auditing
- dry-run policy rollout
- namespace exemptions
- policy troubleshooting
- governance reporting
- secure workload admission
- non-root workload enforcement
- privileged-container restriction
- DevSecOps governance automation

## Real-World Use Case

A platform or security engineering team can use this architecture to enforce Kubernetes security requirements consistently across development, staging, and production clusters.

Instead of relying on manual review, workloads are automatically evaluated against organizational policy during admission. Violating workloads can be rejected immediately, while Gatekeeper audit continuously identifies existing resources that drift from expected controls.

Dry-run policies allow new governance requirements to be evaluated safely before enforcement, helping teams understand operational impact and remediate workloads before switching to blocking mode.

This pattern is directly applicable to environments implementing internal security baselines and external compliance requirements.

## Lessons Learned

- Kubernetes admission control converts security requirements into enforceable platform guardrails.
- Gatekeeper separates reusable policy logic from policy configuration through ConstraintTemplates and Constraints.
- Policy scope must be carefully designed so system namespaces and policy controllers do not block themselves.
- Dry-run evaluation is valuable before enabling new controls in enforce mode.
- Namespace exemptions should be explicit, minimal, documented, and regularly reviewed.
- Deployment-level governance often depends on evaluating the Pods generated by higher-level controllers.
- Continuous audit complements admission enforcement by detecting existing resources that violate current policy.
- Compliance evidence becomes significantly more useful when generated automatically from cluster state.

## Troubleshooting Log

### Missing Kubernetes Cluster

The environment initially provided kubectl but no active Kubernetes context or reachable cluster.

A clean kind cluster was provisioned before Gatekeeper installation.

### Outdated Gatekeeper Installation Method

An older static manifest release was avoided.

Gatekeeper was installed using its Helm chart so installation remained compatible with the current Kubernetes environment.

### ConstraintTemplate Schema Modernization

Current ConstraintTemplates used:

```text
templates.gatekeeper.sh/v1
```

with structural OpenAPI schemas.

This avoided legacy template schema assumptions.

### Rego Policy Syntax

Policies were implemented using current Rego-compatible Gatekeeper template definitions rather than legacy syntax.

### Deployment Enforcement Behavior

A violating Deployment object could exist because the Constraints target Pods.

Gatekeeper blocked the Pod CREATE operations generated by the Deployment controller, demonstrating that enforcement was functioning at the intended resource boundary.

### Dry-Run Interaction

An existing deny constraint would have blocked the dry-run test before the dry-run policy could demonstrate non-blocking behavior.

A dedicated namespace was temporarily excluded from the deny constraint so the dry-run Constraint could audit the violation independently.

### Namespace Exemption Testing

A root-running workload was admitted in an explicitly exempt namespace, proving that Constraint scope and exclusions were functioning correctly.

After validation, temporary exemptions were removed from the final enforced policy.

## Final Validation

The completed governance workflow demonstrated:

```text
Manifest Submission
        │
        ▼
Kubernetes API Server
        │
        ▼
OPA Gatekeeper
        │
        ├──── ConstraintTemplate
        │
        ├──── Constraint
        │
        ├──── Rego Evaluation
        │
        ▼
Compliance Decision
   ┌───────────────┐
   │               │
 COMPLIANT      VIOLATION
   │               │
   ▼               ▼
 ADMIT            DENY
                   │
                   ▼
            Workload Blocked
```

Final validated outcomes:

- Gatekeeper was installed and operational
- ConstraintTemplates were successfully registered
- non-root workload policy was enforced
- privileged-container policy was enforced
- non-compliant workloads were denied
- compliant workloads were admitted
- Deployment-generated Pods were governed
- continuous audit status was captured
- namespace exemptions were validated
- dry-run evaluation was validated
- compliance reports were generated
- troubleshooting reports were generated
- final deny policies remained active after cleanup
- temporary test resources were removed

