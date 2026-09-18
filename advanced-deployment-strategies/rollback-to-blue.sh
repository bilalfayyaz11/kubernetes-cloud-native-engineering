#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="deployment-strategies"

echo "Switching production selector to Blue..."

kubectl patch service sample-app-service \
  -n "$NAMESPACE" \
  -p '{"spec":{"selector":{"app":"sample-app","version":"v1"}}}'

echo
echo "Blue EndpointSlices:"

kubectl get endpointslice \
  -n "$NAMESPACE" \
  -l kubernetes.io/service-name=sample-app-service \
  -o wide
