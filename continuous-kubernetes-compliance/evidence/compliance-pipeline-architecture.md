# Kubernetes Compliance Pipeline

## Detection Layer

```text
Kubernetes Cluster
      |
      +--> kube-bench
      |      |
      |      +--> CIS benchmark findings
      |
      +--> Polaris
             |
             +--> workload best-practice findings
```

## Normalization Layer

```text
kube-bench JSON
       \
        \
         +--> Unified Scoring Contract
        /
       /
Polaris JSON
```

## Decision Contract

```text
kube-bench FAIL > 0
        |
        +--> exit 2

warnings / best-practice findings only
        |
        +--> exit 1

clean
        |
        +--> exit 0
```

## Unified Score

```text
60% kube-bench posture
+
40% Polaris posture
```

The score provides a human-readable posture metric.

The exit code provides a deterministic automation interface suitable for CI/CD gating.
