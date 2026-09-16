#!/usr/bin/env bash

echo "=========================================="
echo " Kubernetes Compliance Status"
echo "=========================================="
echo

echo "1. Gatekeeper System Status"
echo "------------------------------------------"
kubectl get pods \
  -n gatekeeper-system \
  --no-headers \
  2>/dev/null \
  | awk '{printf "%-55s %s\n", $1, $3}'
echo

echo "2. Active Constraint Templates"
echo "------------------------------------------"
kubectl get constrainttemplates \
  --no-headers \
  2>/dev/null \
  | awk '{print "- " $1}'
echo

echo "3. Active Constraints"
echo "------------------------------------------"

kubectl get k8srequirenonroot \
  --no-headers \
  2>/dev/null \
  | awk '{print "- K8sRequireNonRoot/" $1}'

kubectl get k8sdeniesprivileged \
  --no-headers \
  2>/dev/null \
  | awk '{print "- K8sDeniesPrivileged/" $1}'

echo

echo "4. Policy Violations Summary"
echo "------------------------------------------"

NONROOT_VIOLATIONS=$(
  kubectl get k8srequirenonroot \
    must-run-as-non-root \
    -o jsonpath='{.status.totalViolations}' \
    2>/dev/null
)

PRIVILEGED_VIOLATIONS=$(
  kubectl get k8sdeniesprivileged \
    no-privileged-containers \
    -o jsonpath='{.status.totalViolations}' \
    2>/dev/null
)

echo "- must-run-as-non-root: ${NONROOT_VIOLATIONS:-0}"
echo "- no-privileged-containers: ${PRIVILEGED_VIOLATIONS:-0}"
echo

echo "5. Potentially Non-Compliant Pods"
echo "------------------------------------------"

kubectl get pods \
  --all-namespaces \
  -o json \
  | jq -r '
      .items[]
      | . as $pod
      | [
          .spec.containers[]?
          | select(
              (.securityContext.runAsUser == 0)
              or
              (.securityContext.privileged == true)
            )
        ]
      | select(length > 0)
      | "\($pod.metadata.namespace)/\($pod.metadata.name)"
    ' \
  2>/dev/null \
  | sort -u

echo

echo "6. Compliant Application Pods"
echo "------------------------------------------"

kubectl get pods \
  -n default \
  -l app=compliant-app \
  --no-headers \
  2>/dev/null \
  | awk '{print "- " $1 ": " $3}'

echo
echo "=========================================="
echo " Compliance Check Complete"
echo "=========================================="
