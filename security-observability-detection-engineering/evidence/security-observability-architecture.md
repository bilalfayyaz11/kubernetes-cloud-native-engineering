# Security Observability Architecture

## Metrics Pipeline

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

## Log Detection Pipeline

```text
Structured Security Events
           |
           v
      NDJSON Log
           |
           v
 Python Analysis Engine
           |
           +--> Event Counts
           |
           +--> Brute-Force Detection
           |
           +--> Critical Alert Extraction
           |
           +--> Investigation Timeline
```

## Security Signals

The observability pipeline evaluates:

- failed authentication rate
- repeated failures by source IP
- abnormal request bursts
- elevated API response latency
- critical structured security events
- suspicious HTTP response patterns

## Detection Flow

```text
Telemetry
   |
   v
Collection
   |
   v
PromQL / Python Detection
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
