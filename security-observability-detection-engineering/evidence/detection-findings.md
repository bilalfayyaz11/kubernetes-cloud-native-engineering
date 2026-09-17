# Security Detection Findings

## Structured Logging

Format:

NDJSON

Each event includes at minimum:

- timestamp
- hostname
- event_type

Additional fields depend on the security event.

## Brute-Force Detection

Controlled source:

`10.0.0.66`

Observed failed logins:

`8`

Threshold:

`5`

Detection result:

DETECTED

## Critical Alert Detection

Matching critical brute-force alerts:

`1`

## Detection Logic

The analysis pipeline:

1. parses NDJSON safely;
2. skips malformed entries;
3. counts failed authentication events by source IP;
4. identifies sources exceeding the configured threshold;
5. extracts critical security alerts;
6. summarizes HTTP anomaly patterns.

## Security Engineering Value

The log pipeline separates:

```text
raw events
    |
    v
structured telemetry
    |
    v
detection logic
    |
    v
security finding
```

This allows the same event stream to support both automated detection and human investigation.
