#!/usr/bin/env bash

set +e

echo "===== WEBAPP RESOURCES ====="
kubectl get webapps -o wide

echo
echo "===== CONTROLLER ====="
kubectl get deployment webapp-controller -o wide

echo
echo "===== MANAGED DEPLOYMENTS ====="
kubectl get deployments \
  -l app.kubernetes.io/managed-by=webapp-controller \
  -o wide

echo
echo "===== MANAGED SERVICES ====="
kubectl get services \
  -l app.kubernetes.io/managed-by=webapp-controller \
  -o wide

echo
echo "===== MANAGED PODS ====="
kubectl get pods \
  -l app.kubernetes.io/managed-by=webapp-controller \
  -o wide

echo
echo "===== WEBAPP STATUS ====="
kubectl get webapps \
  -o custom-columns='NAME:.metadata.name,GENERATION:.metadata.generation,OBSERVED:.status.observedGeneration,DESIRED:.spec.replicas,AVAILABLE:.status.availableReplicas,READY:.status.conditions[0].status,IMAGE:.spec.image,PORT:.spec.port'

echo
echo "===== CONTROLLER LOGS ====="
kubectl logs \
  -l app.kubernetes.io/name=webapp-controller \
  --tail=40
