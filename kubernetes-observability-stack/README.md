# Kubernetes Observability with Prometheus, Grafana and Alertmanager

## What This Does

This implementation provides end-to-end Kubernetes observability using Prometheus Operator, Grafana, Alertmanager, kube-state-metrics, node-exporter, and application-native metrics exported from nginx. It collects infrastructure and workload telemetry, evaluates custom PromQL alert conditions, routes firing alerts through Alertmanager, and presents operational signals through reproducible Grafana dashboards. Application metrics are discovered declaratively through ServiceMonitor resources, while recording rules precompute frequently used queries for efficient reuse across dashboards, alerts, and operational automation.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                               │
│                                                                         │
│  ┌────────────────────── Application Layer ─────────────────────────┐   │
│  │                                                                  │   │
│  │  ┌───────────────────────────────────────────────────────────┐   │   │
│  │  │ sample-web-app Deployment                                │   │   │
│  │  │                                                           │   │   │
│  │  │  ┌─────────────────┐     ┌────────────────────────────┐   │   │   │
│  │  │  │ nginx           │────▶│ nginx-prometheus-exporter │   │   │   │
│  │  │  │ :80             │     │ :9113 /metrics            │   │   │   │
│  │  │  │ /nginx_status   │     └─────────────┬──────────────┘   │   │   │
│  │  │  └─────────────────┘                   │                  │   │   │
│  │  └────────────────────────────────────────┼──────────────────┘   │   │
│  │                                           │                      │   │
│  │  ┌──────────────────────┐                 │                      │   │
│  │  │ Load Generator       │──── HTTP ──────▶│ Kubernetes Service   │   │
│  │  └──────────────────────┘                 │                      │   │
│  └───────────────────────────────────────────┼──────────────────────┘   │
│                                              │                          │
│                                   ServiceMonitor discovery              │
│                                              │                          │
│                                              ▼                          │
│  ┌──────────────────── Observability Layer ─────────────────────────┐   │
│  │                                                                  │   │
│  │  ┌────────────────────┐       ┌──────────────────────────────┐   │   │
│  │  │ Prometheus         │◀──────│ Prometheus Operator          │   │   │
│  │  │                    │       │                              │   │   │
│  │  │ • metric scraping  │       │ • ServiceMonitor discovery  │   │   │
│  │  │ • PromQL queries   │       │ • PrometheusRule lifecycle  │   │   │
│  │  │ • rule evaluation  │       └──────────────────────────────┘   │   │
│  │  └──────────┬─────────┘                                          │   │
│  │             │                                                    │   │
│  │             ├──────────────▶ ┌───────────────────────┐            │   │
│  │             │                │ Grafana               │            │   │
│  │             │                │ • cluster telemetry   │            │   │
│  │             │                │ • app performance     │            │   │
│  │             │                └───────────────────────┘            │   │
│  │             │                                                    │   │
│  │             └─ firing alerts ─▶ ┌───────────────────────┐         │   │
│  │                                │ Alertmanager          │         │   │
│  │                                │ alert lifecycle       │         │   │
│  │                                └───────────────────────┘         │   │
│  │                                                                  │   │
│  │  ┌────────────────────┐       ┌──────────────────────────────┐   │   │
│  │  │ node-exporter      │       │ kube-state-metrics           │   │   │
│  │  │ host telemetry     │       │ Kubernetes object metrics    │   │   │
│  │  └────────────────────┘       └──────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│        Persistent storage through dynamically provisioned PVCs          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Linux host with at least 2 vCPU and approximately 4 GiB RAM
- sudo privileges
- Internet access for Helm charts and container images
- Kubernetes cluster
- kubectl
- Helm
- curl
- Python 3
- Default Kubernetes StorageClass
- Permissions to create monitoring CRDs, RBAC resources, Deployments, Services, ConfigMaps, and PVCs

Validated environment:

- Ubuntu 24.04
- K3s single-node Kubernetes
- Helm 4
- kube-prometheus-stack 91.5.0
- Prometheus 3.14
- Grafana 13.2
- Alertmanager 0.34
- nginx 1.28 Alpine
- nginx-prometheus-exporter 1.4.2

## Setup & Installation

When an existing Kubernetes cluster is unavailable, a lightweight K3s environment can be initialized with:

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 644" \
  sh -

mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

export KUBECONFIG="$HOME/.kube/config"

kubectl wait \
  --for=condition=Ready \
  node \
  --all \
  --timeout=180s
```

Install the monitoring stack:

```bash
kubectl create namespace monitoring \
  --dry-run=client \
  -o yaml | kubectl apply -f -

helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts \
  --force-update

helm repo update

helm upgrade --install prometheus \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring-values.yaml \
  --wait \
  --timeout 10m
```

Verify the monitoring components:

```bash
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
kubectl get prometheus -n monitoring
kubectl get alertmanager -n monitoring
```

## How to Reproduce

Apply custom resource alerts and the controlled CPU workload:

```bash
kubectl apply -f prometheus-alerts.yaml
kubectl apply -f cpu-stress-test.yaml
```

Deploy the observable web application:

```bash
kubectl apply -f nginx-observability-config.yaml
kubectl apply -f sample-app-observability.yaml
kubectl apply -f load-generator.yaml

kubectl rollout status \
  deployment/sample-web-app \
  --timeout=180s
```

Configure application metric discovery and reusable recording rules:

```bash
kubectl apply -f service-monitor.yaml
kubectl apply -f recording-rules.yaml
```

Verify the monitoring resources:

```bash
kubectl get servicemonitor \
  sample-web-app-monitor \
  -n monitoring

kubectl get prometheusrule \
  kubernetes-resource-alerts \
  kubernetes-observability-recording-rules \
  -n monitoring
```

Access Prometheus:

```bash
kubectl port-forward \
  -n monitoring \
  svc/prometheus-kube-prometheus-prometheus \
  9090:9090
```

Prometheus becomes available at:

```text
http://127.0.0.1:9090
```

Access Grafana in another terminal:

```bash
kubectl port-forward \
  -n monitoring \
  svc/prometheus-grafana \
  3000:80
```

Retrieve the Grafana administrative credential:

```bash
kubectl get secret \
  -n monitoring \
  prometheus-grafana \
  -o jsonpath='{.data.admin-password}' \
  | base64 -d

echo
```

Grafana becomes available at:

```text
http://127.0.0.1:3000
```

Import the Kubernetes resource dashboard:

```bash
GRAFANA_PASSWORD="$(
  kubectl get secret \
    -n monitoring \
    prometheus-grafana \
    -o jsonpath='{.data.admin-password}' \
  | base64 -d
)"

curl \
  -u "admin:${GRAFANA_PASSWORD}" \
  -H "Content-Type: application/json" \
  -X POST \
  http://127.0.0.1:3000/api/dashboards/db \
  --data-binary @kubernetes-dashboard.json
```

Import the application performance dashboard:

```bash
curl \
  -u "admin:${GRAFANA_PASSWORD}" \
  -H "Content-Type: application/json" \
  -X POST \
  http://127.0.0.1:3000/api/dashboards/db \
  --data-binary @custom-dashboard.json
```

Validate native nginx metrics:

```bash
EXPORTER_POD="$(
  kubectl get pods \
    -l app=sample-web-app \
    -o jsonpath='{.items[0].metadata.name}'
)"

kubectl port-forward \
  pod/"${EXPORTER_POD}" \
  19113:9113
```

Then query:

```bash
curl http://127.0.0.1:19113/metrics | grep '^nginx_'
```

Useful PromQL queries:

```promql
sum by (namespace, pod) (
  rate(container_cpu_usage_seconds_total{
    container!="",
    container!="POD"
  }[2m])
)
```

```promql
sum by (namespace, pod) (
  container_memory_working_set_bytes{
    container!="",
    container!="POD"
  }
)
```

```promql
nginx_connections_active
```

```promql
application:nginx_active_connections
```

## Tools Used

- Kubernetes
- K3s
- kubectl
- Helm
- Prometheus
- Prometheus Operator
- PromQL
- Grafana
- Alertmanager
- kube-state-metrics
- node-exporter
- nginx
- nginx-prometheus-exporter
- ServiceMonitor
- PrometheusRule
- ConfigMaps
- Kubernetes Services
- PersistentVolumeClaims
- Python 3
- curl

## Key Skills Demonstrated

- Kubernetes observability architecture using Prometheus Operator
- Infrastructure, container, Kubernetes-object, and application metric collection
- PromQL authoring for CPU, memory, filesystem, and application telemetry
- Cross-namespace ServiceMonitor discovery
- PrometheusRule configuration for alerting and metric precomputation
- End-to-end alert verification from workload threshold to Alertmanager
- Grafana dashboard automation through JSON and HTTP APIs
- Resource-aware monitoring deployment on constrained infrastructure
- Persistent observability storage through dynamically provisioned PVCs
- Exporter integration for software without native Prometheus instrumentation
- Kubernetes health probes, resource requests, and resource limits
- Troubleshooting across Helm, Kubernetes, Prometheus Operator, Grafana, PromQL, and metric discovery

## Real-World Use Case

This architecture fits Kubernetes platform and AIOps environments that require centralized visibility into cluster health and application behavior before degradation becomes customer-facing. Prometheus continuously collects operational telemetry, recording rules provide reusable precomputed metrics, Grafana presents infrastructure and application signals, and Alertmanager receives threshold violations for integration with downstream incident-management systems. Exporter-based application instrumentation also provides a practical observability path for existing services that do not expose Prometheus metrics natively.

## Lessons Learned

- Kubernetes monitoring stacks must be sized according to actual cluster CPU, memory, and storage capacity.
- Successful creation of a Prometheus Operator custom resource does not guarantee immediate discovery because reconciliation occurs asynchronously.
- ServiceMonitor configuration must match both Service labels and the namespace containing the monitored Service.
- Standard nginx does not expose Prometheus metrics directly and requires an exporter or native instrumentation layer.
- Programmatic JSON serialization prevents shell-escaping problems when Grafana dashboard definitions contain nested PromQL expressions.

## Troubleshooting Log

### Missing Kubernetes Cluster

The host contained kubectl and Helm but initially had no Kubernetes context or reachable API server. A single-node K3s environment supplied the control plane, kubeconfig, metrics-server, and local-path storage required by the monitoring stack.

### Grafana Startup Readiness

Grafana temporarily remained partially ready while its container image was downloaded and initialization completed. Kubernetes reported readiness and liveness probe failures followed by one container restart. Grafana subsequently became healthy and the Helm release completed successfully.

### Malformed Grafana Dashboard JSON

Dashboard creation initially returned HTTP 400. Local JSON validation identified invalid syntax caused by shell escaping inside PromQL expressions embedded in a heredoc. Dashboard generation was moved to Python JSON serialization so nested quoting was handled deterministically before API submission.

### PrometheusRule Reconciliation Delay

Custom alert rules passed Kubernetes API validation and carried the expected `release=prometheus` label but were not immediately visible through the Prometheus API. Inspection confirmed that the live Prometheus selector matched the resource. After Prometheus Operator reconciliation, all custom rules appeared and entered active evaluation.

### CPU Alert Threshold Alignment

The original CPU alert threshold exceeded the resource limit of the workload intended to trigger it. The threshold and controlled workload were aligned so the alert could transition through pending and firing states and reach Alertmanager.

### Invalid nginx Metrics Assumption

Standard nginx did not provide a Prometheus `/metrics` endpoint. nginx `stub_status` and nginx-prometheus-exporter were added, a dedicated `metrics` Service port was exposed on port 9113, and ServiceMonitor was configured to discover the Service across namespaces.

### ServiceMonitor Scrape Synchronization

Prometheus successfully discovered all three nginx exporter endpoints, but their initial health state appeared as `unknown`. The targets had only just been reconciled and had not completed their first configured scrape interval. After the first scrape cycle, target health could be evaluated normally.

### Alertmanager Localhost Receiver

A webhook receiver configured as `localhost` inside Alertmanager would reference the Alertmanager container's own network namespace rather than an external notification service. The alert pipeline was therefore validated through Prometheus and Alertmanager without committing an unreachable receiver configuration.
