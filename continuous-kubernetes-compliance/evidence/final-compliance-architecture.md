# Kubernetes Continuous Compliance Architecture

```text
                    Kubernetes
                        |
            +-----------+-----------+
            |                       |
            v                       v
        kube-bench                Polaris
      CIS Benchmark          Workload Practices
            |                       |
            +-----------+-----------+
                        |
                        v
                 JSON Normalization
                        |
                        v
                 Unified Scoring
                        |
                 +------+------+
                 |             |
                 v             v
             Human Score   Exit 0/1/2
                               |
                               v
                           CI/CD Gate
                               |
                               v
                        OPA Gatekeeper
                               |
                    +----------+----------+
                    |                     |
                    v                     v
                  DENY                  ADMIT
             weak workload        hardened workload
                                          |
                                          v
                                    Re-scan Polaris
                                          |
                                          v
                                   Verify Improvement
```

## Compliance Layers

### Detection

kube-bench evaluates Kubernetes node and control-plane posture.

Polaris evaluates workload configuration and operational security practices.

### Decision

Structured scanner output is normalized into one compliance contract.

The weighted score is:

```text
60% kube-bench
40% Polaris
```

The automation contract uses:

```text
2 = critical CIS failures
1 = warnings / best-practice findings
0 = clean
```

### Prevention

OPA Gatekeeper prevents workloads from entering the cluster when mandatory controls are missing.

### Verification

A remediated workload is admitted and re-scanned to demonstrate measurable improvement.
