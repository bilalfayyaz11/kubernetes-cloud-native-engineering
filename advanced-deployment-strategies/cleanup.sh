#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="deployment-strategies"

echo "Removing Kubernetes resources..."

pkill -f \
  "kubectl port-forward" \
  2>/dev/null || true

kubectl delete namespace "$NAMESPACE" \
  --ignore-not-found

echo "Kubernetes resources removed."
echo "Local manifests and evidence remain preserved."
