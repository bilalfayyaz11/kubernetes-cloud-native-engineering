# Continuous Kubernetes Compliance

A Kubernetes compliance automation implementation combining CIS benchmark scanning, workload best-practice auditing, unified risk scoring, and admission-time policy enforcement.

The architecture closes the loop between detecting drift and preventing non-compliant workloads from entering the cluster.

## Architecture

```text
                    Kubernetes Cluster
                           |
               +-----------+-----------+
               |                       |
               v                       v
           kube-bench                Polaris
         CIS Benchmark          Workload Audit
               |                       |
               +-----------+-----------+
                           |
                           v
                  Unified Scoring
                           |
                    exit 0 / 1 / 2
                           |
                           v
                     CI/CD Decision
                           |
                           v
                    OPA Gatekeeper
                           |
                +----------+----------+
                |                     |
                v                     v
              DENY                  ADMIT
       non-compliant workload    compliant workload
                                      |
                                      v
                                Re-scan Polaris
                                      |
                                      v
                               Verify Improvement
```

## Objectives

This implementation demonstrates:

```text
Kubernetes CIS benchmarking
workload best-practice auditing
structured JSON compliance reporting
unified compliance scoring
deterministic automation exit codes
admission-time policy enforcement
security remediation
post-remediation validation
```

## Compliance Toolchain

```text
kube-bench
Polaris
OPA Gatekeeper
Rego
kubectl
jq
shell automation
```

## Layer 1 — Cluster Benchmarking

kube-bench evaluates Kubernetes control-plane and node configuration against CIS-oriented benchmark checks.

The scan produces structured JSON containing:

```text
PASS controls
FAIL controls
WARN controls
control IDs
control descriptions
```

These findings provide cluster-level security posture information.

## Layer 2 — Workload Best-Practice Auditing

Polaris evaluates Kubernetes workloads against operational and security best practices.

The deliberately weak workload is designed to expose multiple issues:

```text
no CPU limits
no memory limits
no requests
no securityContext
runs without explicit non-root enforcement
no liveness probe
no readiness probe
```

This creates a measurable baseline posture.

## Deliberately Non-Compliant Workload

The baseline Deployment intentionally omits controls.

```yaml
image: nginx:1.25-alpine
```

It contains:

```text
no resource requests
no resource limits
no runAsNonRoot
no allowPrivilegeEscalation control
no dropped capabilities
no liveness probe
no readiness probe
```

The workload exists only to generate meaningful compliance findings.

## Unified Compliance Scoring

Both scanner outputs are normalized through a shell-based scoring contract.

The weighted score is:

```text
(kube_pass / (kube_pass + kube_fail)) * 0.6
+
(polaris_score / 100) * 0.4
```

This produces one percentage representing overall cluster and workload posture.

## Deterministic Exit Contract

The scoring engine also exposes a machine-readable automation interface.

```text
exit 2 = kube-bench failures exist
exit 1 = warnings / best-practice findings only
exit 0 = clean
```

This makes the compliance result usable directly in CI/CD pipelines.

## Why Exit Codes Matter

The score is useful for humans.

The exit code is useful for automation.

```text
Compliance Scan
      |
      v
Unified Contract
      |
      +--> Score for dashboards
      |
      +--> Exit code for pipelines
```

A CI/CD system can therefore stop deployment when posture does not meet policy.

## Gatekeeper Admission Enforcement

OPA Gatekeeper provides prospective enforcement.

Two mandatory controls are implemented.

### Resource Limits

Every Deployment container must define:

```text
resources.limits.cpu
resources.limits.memory
```

A missing limit produces a descriptive admission violation naming the offending container.

### Non-Root Execution

Every Deployment must define:

```text
pod securityContext.runAsNonRoot: true
```

and every container must also define:

```text
securityContext.runAsNonRoot: true
```

## Rego v1 Policies

The ConstraintTemplates use modern Rego v1 syntax.

Example policy pattern:

```rego
violation contains {"msg": msg} if {
    container := input.review.object.spec.template.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf(
        "container %q must define resources.limits.cpu",
        [container.name]
    )
}
```

This turns compliance requirements into executable policy.

## Admission Control Flow

```text
kubectl apply
     |
     v
Kubernetes API Server
     |
     v
Gatekeeper Webhook
     |
     v
Rego Evaluation
     |
 +---+---+
 |       |
 v       v
DENY    ALLOW
```

The non-compliant workload is rejected before persistence.

## Hardened Replacement

The compliant workload adds:

```text
runAsNonRoot: true
runAsUser >= 1000
allowPrivilegeEscalation: false
capabilities.drop: ALL
CPU requests
memory requests
CPU limits
memory limits
liveness probe
readiness probe
```

This allows it to satisfy both mandatory Gatekeeper controls while substantially improving its Polaris posture.

## Remediation Loop

```text
Weak Deployment
      |
      v
Polaris Baseline
      |
      v
Gatekeeper DENY
      |
      v
Security Remediation
      |
      v
Compliant Deployment
      |
      v
Polaris Re-scan
      |
      v
Measured Improvement
```

This proves that remediation is not merely theoretical.

## Compliance as Code

The implementation treats compliance as executable infrastructure.

```text
Benchmark definitions
        +
Scanner output
        +
Scoring logic
        +
Admission policy
        +
Remediation validation
```

The result is a repeatable control system instead of a manual checklist.

## Detection vs Prevention

The architecture intentionally combines two different control types.

### Retrospective Controls

```text
kube-bench
Polaris
```

These inspect existing state.

They answer:

```text
What is currently wrong?
```

### Prospective Controls

```text
OPA Gatekeeper
```

This evaluates new workload admission.

It answers:

```text
Should this resource be allowed to exist?
```

Using both prevents compliance from becoming purely reactive.

## Repository Structure

```text
continuous-kubernetes-compliance/
├── README.md
├── .gitignore
├── manifests/
│   ├── noncompliant-app.yaml
│   ├── compliant-app.yaml
│   ├── require-resource-limits-template.yaml
│   ├── require-resource-limits.yaml
│   ├── require-nonroot-template.yaml
│   └── require-nonroot.yaml
├── scripts/
│   └── unified-report.sh
└── evidence/
    ├── environment validation
    ├── scanner versions
    ├── kube-bench findings
    ├── Polaris findings
    ├── unified compliance reports
    ├── Gatekeeper admission evidence
    ├── remediation comparison
    └── final validation
```

## Security Engineering Outcomes

The implementation proves:

```text
cluster CIS scanning                  IMPLEMENTED
workload compliance scanning          IMPLEMENTED
structured report parsing             IMPLEMENTED
weighted compliance scoring           IMPLEMENTED
deterministic CI/CD exit contract      IMPLEMENTED
admission policy enforcement           IMPLEMENTED
negative admission testing             VALIDATED
hardened workload admission            VALIDATED
post-remediation re-scanning           VALIDATED
```

## CI/CD Integration Model

A future pipeline can use the scoring script directly:

```text
Build
  |
  v
Deploy to test cluster
  |
  v
kube-bench + Polaris
  |
  v
Unified Scoring Script
  |
  +--> exit 0 -> continue
  |
  +--> exit 1 -> warning / review
  |
  +--> exit 2 -> block pipeline
```

Admission-time policy provides an additional control even if a pipeline gate is bypassed.

## Defense in Depth

```text
CI/CD Compliance Gate
          |
          v
Kubernetes API
          |
          v
Gatekeeper Admission
          |
          v
Runtime Cluster
          |
          v
Periodic kube-bench / Polaris
```

No single compliance layer is treated as sufficient by itself.

## Production Extensions

A production implementation could add:

```text
GitHub Actions or GitLab CI integration
scheduled compliance scans
Prometheus compliance metrics
Grafana posture dashboards
Slack / Teams notifications
OPA policy unit tests
Policy-as-code repositories
namespace-specific compliance profiles
CIS control severity weighting
exception management
audit evidence retention
multi-cluster aggregation
ticketing integration
continuous drift detection
```

## Key Takeaway

Continuous Kubernetes compliance is not just scanning.

The complete lifecycle is:

```text
Measure
   |
   v
Normalize
   |
   v
Score
   |
   v
Decide
   |
   v
Prevent
   |
   v
Remediate
   |
   v
Re-Measure
```

This implementation demonstrates that full lifecycle using Kubernetes-native and open-source security tooling.
