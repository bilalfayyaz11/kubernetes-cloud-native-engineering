#!/bin/bash
set +e

echo "=================================================="
echo " CONTAINER SECURITY PROFILE MONITORING"
echo "=================================================="

echo
echo "===== APPARMOR PROFILE STATUS ====="
sudo aa-status | grep -F 'containers.restricted-container' \
  || echo "Custom AppArmor profile not found"

echo
echo "===== RECENT APPARMOR DENIALS ====="
sudo dmesg \
  | grep -i 'apparmor="DENIED"' \
  | tail -n 10 \
  || true

echo
echo "===== RECENT KERNEL SECURITY EVENTS ====="
sudo journalctl \
  -k \
  --no-pager \
  | grep -Ei 'apparmor="DENIED"|seccomp' \
  | tail -n 20 \
  || true

echo
echo "===== POD SECURITY CONTEXTS ====="

for pod in seccomp-test-pod apparmor-test-pod hardened-test-pod; do
  echo
  echo "--- $pod ---"

  kubectl get pod "$pod" \
    -o jsonpath='
name={.metadata.name}{"\n"}
podRunAsNonRoot={.spec.securityContext.runAsNonRoot}{"\n"}
podRunAsUser={.spec.securityContext.runAsUser}{"\n"}
podSeccompType={.spec.securityContext.seccompProfile.type}{"\n"}
podSeccompProfile={.spec.securityContext.seccompProfile.localhostProfile}{"\n"}
containerRunAsNonRoot={.spec.containers[0].securityContext.runAsNonRoot}{"\n"}
containerRunAsUser={.spec.containers[0].securityContext.runAsUser}{"\n"}
appArmorType={.spec.containers[0].securityContext.appArmorProfile.type}{"\n"}
appArmorProfile={.spec.containers[0].securityContext.appArmorProfile.localhostProfile}{"\n"}
allowPrivilegeEscalation={.spec.containers[0].securityContext.allowPrivilegeEscalation}{"\n"}
readOnlyRootFilesystem={.spec.containers[0].securityContext.readOnlyRootFilesystem}{"\n"}
capabilitiesDropped={.spec.containers[0].securityContext.capabilities.drop}{"\n"}
' 2>/dev/null || true
done

echo
echo "===== HARDENED POD STATUS ====="
kubectl get pod hardened-test-pod -o wide

echo
echo "===== HARDENED POD RESOURCES ====="
kubectl get pod hardened-test-pod \
  -o jsonpath='CPU-request={.spec.containers[0].resources.requests.cpu}{"\n"}CPU-limit={.spec.containers[0].resources.limits.cpu}{"\n"}Memory-request={.spec.containers[0].resources.requests.memory}{"\n"}Memory-limit={.spec.containers[0].resources.limits.memory}{"\n"}'

echo
echo "===== HARDENED PROCESS SECURITY FIELDS ====="
kubectl exec hardened-test-pod -- sh -c '
grep -E "^NoNewPrivs:|^Cap(Inh|Prm|Eff|Bnd|Amb):" /proc/1/status
' 2>/dev/null || true

echo
echo "=================================================="
echo " SECURITY MONITORING COMPLETE"
echo "=================================================="
