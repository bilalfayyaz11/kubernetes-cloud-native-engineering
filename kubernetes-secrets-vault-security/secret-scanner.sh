#!/bin/bash
set +e

echo "=================================================="
echo " KUBERNETES SECRET EXPOSURE SCAN"
echo "=================================================="

echo
echo "===== INLINE ENVIRONMENT VALUES WITH SENSITIVE NAMES ====="

INLINE_ENV="$(
  kubectl get pods -A -o json \
  | jq -r '
      .items[]
      | . as $pod
      | .spec.containers[]?
      | . as $container
      | .env[]?
      | select(
          (.name | test("password|secret|token|api[_-]?key|credential"; "i"))
          and (.value != null)
        )
      | "\($pod.metadata.namespace)/\($pod.metadata.name) container=\($container.name) env=\(.name)"
    '
)"

if [ -n "$INLINE_ENV" ]; then
  echo "$INLINE_ENV"
  echo "WARNING: possible plaintext sensitive environment values found"
else
  echo "PASS: no obvious sensitive inline environment values detected"
fi

echo
echo "===== SECRETKEYREF USAGE ====="

kubectl get pods -A -o json \
  | jq -r '
      .items[]
      | . as $pod
      | .spec.containers[]?
      | . as $container
      | .env[]?
      | select(.valueFrom.secretKeyRef != null)
      | "\($pod.metadata.namespace)/\($pod.metadata.name) container=\($container.name) env=\(.name) secret=\(.valueFrom.secretKeyRef.name) key=\(.valueFrom.secretKeyRef.key)"
    '

echo
echo "===== SECRET VOLUME USAGE ====="

kubectl get pods -A -o json \
  | jq -r '
      .items[]
      | . as $pod
      | .spec.volumes[]?
      | select(.secret != null)
      | "\($pod.metadata.namespace)/\($pod.metadata.name) volume=\(.name) secret=\(.secret.secretName)"
    '

echo
echo "===== SUSPICIOUS INLINE MANIFEST STRINGS ====="

kubectl get pods -A -o json \
  | jq -r '
      .items[]
      | .metadata.namespace as $ns
      | .metadata.name as $pod
      | .spec.containers[]?
      | .name as $container
      | .args[]?,
        .command[]?
      | select(test("password=|token=|api[_-]?key=|secret="; "i"))
      | "\($ns)/\($pod) container=\($container) possible-sensitive-command-content"
    ' \
  | sort -u

echo
echo "=================================================="
echo " SECRET EXPOSURE SCAN COMPLETE"
echo "=================================================="
