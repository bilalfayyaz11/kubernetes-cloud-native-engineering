# Security Observability and Detection Engineering

A security observability implementation built around Prometheus, Alertmanager, Grafana, structured security telemetry, and Python-based detection logic.

The system demonstrates the complete detection lifecycle:

```text
Security Event
     |
     v
Telemetry Collection
     |
     v
Metrics / Structured Logs
     |
     v
Detection Logic
     |
     v
Alert
     |
     v
Routing
     |
     v
Investigation Evidence
```

## Architecture

### Metrics and Alerting Pipeline

```text
Application / Security Events
           |
           v
Custom Security Exporter
           |
           | /metrics
           v
       Prometheus
        /      \
       /        \
      v          v
 Grafana      Alert Rules
                  |
                  v
             Alertmanager
                  |
                  v
           Webhook Receiver
```

### Structured Log Detection Pipeline

```text
Security Events
      |
      v
Structured NDJSON
      |
      v
Python Detection Engine
      |
      +--> Event Classification
      |
      +--> Brute-Force Detection
      |
      +--> Critical Alert Extraction
      |
      +--> Investigation Timeline
```

## Components

```text
Prometheus
Alertmanager
Grafana
Node Exporter
Custom Python Security Exporter
Webhook Receiver
Structured Log Generator
Python Log Analysis Engine
```

## Security Signals

The platform collects and evaluates:

```text
failed authentication attempts
per-IP login failures
HTTP request bursts
API response latency
active sessions
HTTP status anomalies
critical security events
```

## Prometheus Security Metrics

Custom metrics include:

```text
security_login_attempts_total
security_failed_logins_per_ip_total
security_api_response_seconds
security_active_sessions
security_http_requests_total
security_exporter_attack_mode
```

These metrics are exposed by the custom Python exporter and scraped by Prometheus.

## Detection Rules

### High Failed Login Rate

Detects elevated authentication failures.

```promql
rate(security_login_attempts_total{status="failed"}[1m]) > 0.20
```

### Brute-Force Source

Detects repeated authentication failures from the same source.

```promql
rate(security_failed_logins_per_ip_total[1m]) > 0.15
```

### API Latency Anomaly

Detects degraded API response behavior.

```promql
histogram_quantile(
  0.95,
  rate(security_api_response_seconds_bucket[2m])
) > 1.5
```

### Request Burst

Detects abnormal increases in HTTP request volume.

```promql
rate(security_http_requests_total[30s]) > 2
```

## Deterministic Attack Simulation

The exporter supports two operating modes:

```text
normal
attack
```

Normal mode generates low-noise application behavior.

Attack mode deliberately generates:

```text
high failed-login volume
repeated failures from 10.0.0.66
HTTP 401 responses
HTTP 404 bursts
elevated API latency
increased active sessions
```

This makes alert validation repeatable instead of depending on random events.

## Detection Flow

```text
Attack Simulation
       |
       v
Custom Metrics
       |
       v
Prometheus
       |
       v
PromQL Rule Evaluation
       |
       v
Pending
       |
       v
Firing
       |
       v
Alertmanager
       |
       v
Webhook Delivery
```

## Alert Routing

Prometheus is explicitly configured to forward alerts to Alertmanager.

Alertmanager then routes security detections to the local webhook receiver.

This validates the complete signal path:

```text
Detection
   |
   v
Prometheus Alert
   |
   v
Alertmanager
   |
   v
Webhook Receiver
```

## Structured Security Logs

Security events are written in NDJSON format.

Example structure:

```json
{
  "timestamp": "2026-09-17T12:00:00+00:00",
  "hostname": "security-node",
  "event_type": "login_attempt",
  "username": "admin",
  "ip_address": "10.0.0.66",
  "success": false,
  "status": "failed"
}
```

The raw runtime log itself is excluded from repository packaging.

Only sanitized analysis outputs and investigation evidence are retained.

## Brute-Force Detection

The Python detection engine:

```text
reads NDJSON
   |
   v
filters login_attempt events
   |
   v
extracts failed authentication attempts
   |
   v
groups failures by source IP
   |
   v
compares against threshold
   |
   v
flags suspicious source
```

The controlled attack source:

```text
10.0.0.66
```

is deliberately generated with enough failures to exceed the configured threshold.

## Critical Alert Analysis

The analysis engine also extracts:

```text
event_type = security_alert
severity   = critical
```

This allows raw telemetry to be converted into higher-level security findings.

## Detection Outputs

The analysis produces:

```text
event type counts
failed-login source counts
brute-force findings
critical alerts
HTTP status distributions
suspicious HTTP sources
attack timeline
machine-readable JSON findings
```

## Grafana Security Dashboard

The Grafana dashboard is provisioned automatically from source-controlled JSON.

Panels include:

```text
Failed Login Rate
Failed Logins by Source IP
API p95 Latency
HTTP Request Rate
Active Sessions
Attack Simulation Mode
```

No manual dashboard creation is required.

## Dashboard Queries

### Failed Authentication Rate

```promql
rate(security_login_attempts_total{status="failed"}[1m])
```

### Failed Authentication by Source

```promql
rate(security_failed_logins_per_ip_total[1m])
```

### API p95 Latency

```promql
histogram_quantile(
  0.95,
  rate(security_api_response_seconds_bucket[2m])
)
```

### HTTP Request Rate

```promql
rate(security_http_requests_total[30s])
```

## Validation Strategy

The implementation validates the platform from the CLI instead of relying only on visual inspection.

Validation includes:

```text
Prometheus health
Alertmanager health
Grafana health
Node Exporter metrics
Custom exporter metrics
Prometheus target status
Prometheus rule loading
Alertmanager discovery
Grafana datasource provisioning
Grafana dashboard provisioning
PromQL query execution
Alert firing
Webhook delivery
Structured log detection
```

## Security Engineering Outcomes

The implementation proves:

```text
metrics collection                  VALIDATED
PromQL detection logic              VALIDATED
alert evaluation                    VALIDATED
alert routing                       VALIDATED
webhook delivery                    VALIDATED
structured security logging         VALIDATED
brute-force detection               VALIDATED
critical-event extraction           VALIDATED
dashboard provisioning              VALIDATED
```

## Repository Structure

```text
security-observability-detection-engineering/
├── README.md
├── .gitignore
├── compose.yaml
├── prometheus/
│   ├── prometheus.yml
│   └── security-rules.yml
├── alertmanager/
│   └── alertmanager.yml
├── grafana/
│   ├── dashboards/
│   │   └── security-observability.json
│   └── provisioning/
│       ├── dashboards/
│       │   └── security.yml
│       └── datasources/
│           └── prometheus.yml
├── app/
│   ├── exporter.py
│   ├── log_generator.py
│   ├── analyze_logs.py
│   ├── webhook_receiver.py
│   ├── Dockerfile
│   ├── Dockerfile.webhook
│   └── requirements.txt
└── evidence/
    ├── Prometheus target validation
    ├── security alert evidence
    ├── Alertmanager routing evidence
    ├── structured log analysis
    ├── brute-force timeline
    ├── Grafana provisioning validation
    └── final observability assessment
```

## Security Design Principles

### Detection as Code

Prometheus rules, Grafana dashboards, and analysis logic are stored as code instead of configured manually.

### Repeatable Validation

Attack behavior is deterministic enough to validate that detections actually work.

### Signal Separation

The system separates:

```text
telemetry
detection
alerting
routing
investigation
```

instead of treating monitoring as one undifferentiated layer.

### Credential Isolation

Grafana administrator credentials are generated outside the repository and are not stored in Compose or source-controlled files.

### Safe Evidence

Raw runtime logs and credentials are excluded from the portfolio package.

Only sanitized findings and operational validation artifacts are retained.

## Practical Security Use Cases

The architecture can be extended to detect:

```text
credential stuffing
brute-force authentication
HTTP enumeration
unusual request spikes
latency-based degradation
API abuse
suspicious session growth
security control failures
```

## Production Extensions

A production version could add:

```text
Loki
OpenTelemetry
SIEM forwarding
PagerDuty / Slack integration
long-term Prometheus storage
Grafana authentication integration
TLS between monitoring components
centralized secrets management
Falco runtime events
Kubernetes audit events
cloud-provider telemetry
ML-assisted anomaly detection
```

## Key Takeaway

The implementation demonstrates more than dashboard creation.

It shows the full security detection lifecycle:

```text
Generate
   |
   v
Observe
   |
   v
Detect
   |
   v
Alert
   |
   v
Route
   |
   v
Investigate
   |
   v
Validate
```

This turns observability data into actionable security signals rather than passive monitoring.
