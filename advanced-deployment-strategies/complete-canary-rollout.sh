#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="deployment-strategies"

kubectl scale deployment sample-app-v3 \
  -n "$NAMESPACE" \
  --replicas=3

kubectl rollout status deployment/sample-app-v3 \
  -n "$NAMESPACE" \
  --timeout=300s

kubectl scale deployment sample-app-v1 \
  -n "$NAMESPACE" \
  --replicas=0

echo "Canary promoted to full production."
