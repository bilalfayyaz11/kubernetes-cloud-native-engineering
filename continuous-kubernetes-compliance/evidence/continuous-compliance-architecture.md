# Continuous Kubernetes Compliance Architecture

```text
              Kubernetes Cluster
                     |
          +----------+----------+
          |                     |
          v                     v
      kube-bench              Polaris
          |                     |
          +----------+----------+
                     |
                     v
            Unified Scoring
                     |
             exit 0 / 1 / 2
                     |
                     v
              Compliance Gate
                     |
                     v
             OPA Gatekeeper
                     |
          +----------+----------+
          |                     |
          v                     v
        DENY                  ADMIT
   weak workload        compliant workload
                              |
                              v
                         Re-scan Polaris
                              |
                              v
                       Measure Improvement
```

## Control Layers

### Retrospective Detection

kube-bench evaluates node and control-plane configuration against CIS-oriented checks.

Polaris evaluates workload configuration against Kubernetes operational and security best practices.

### Unified Decision

Both scanner outputs are converted into one scoring contract.

The exit code provides a deterministic CI/CD interface:

```text
2 = critical benchmark failures
1 = warning / best-practice findings
0 = clean
```

### Prospective Prevention

Gatekeeper blocks Deployments that violate mandatory controls before they enter the cluster.

### Remediation Verification

A hardened replacement is admitted and then re-scanned to demonstrate measurable posture improvement.
