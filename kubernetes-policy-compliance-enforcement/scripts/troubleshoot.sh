#!/usr/bin/env bash

echo "=========================================="
echo " Gatekeeper Troubleshooting"
echo "=========================================="
echo

echo "1. Gatekeeper Pods"
echo "------------------------------------------"
kubectl get pods \
  -n gatekeeper-system \
  -o wide
echo

echo "2. Gatekeeper Controller Logs"
echo "------------------------------------------"
kubectl logs \
  -n gatekeeper-system \
  -l control-plane=controller-manager \
  --tail=50 \
  --prefix=true \
  2>/dev/null
echo

echo "3. Validating Webhook Configuration"
echo "------------------------------------------"
kubectl get validatingwebhookconfigurations \
  | grep gatekeeper
echo

echo "4. Constraint Templates"
echo "------------------------------------------"
kubectl get constrainttemplates
echo

echo "5. Constraints"
echo "------------------------------------------"
kubectl get k8srequirenonroot
kubectl get k8sdeniesprivileged
echo

echo "6. Constraint Status"
echo "------------------------------------------"
kubectl describe k8srequirenonroot \
  must-run-as-non-root
echo

kubectl describe k8sdeniesprivileged \
  no-privileged-containers
echo

echo "7. Admission API"
echo "------------------------------------------"
kubectl api-resources \
  --api-group=admissionregistration.k8s.io
echo

echo "8. Gatekeeper CRDs"
echo "------------------------------------------"
kubectl get crd \
  | grep gatekeeper
echo

echo "9. Recommended Server-Side Validation"
echo "------------------------------------------"
echo "Use:"
echo "kubectl apply --dry-run=server -f <manifest>"
echo

echo "10. Common Diagnostic Areas"
echo "------------------------------------------"
echo "- Policy not enforcing: inspect enforcementAction and match scope"
echo "- Template errors: inspect ConstraintTemplate status"
echo "- Constraint inactive: confirm generated CRD exists"
echo "- Admission failures: inspect Gatekeeper webhook and controller logs"
echo "- Unexpected exclusions: inspect excludedNamespaces and namespaceSelector"
echo "- Audit mismatch: allow time for audit reconciliation"
echo "- Performance issues: reduce overly broad policy scope"
echo
