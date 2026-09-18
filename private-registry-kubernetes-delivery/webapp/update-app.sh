#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-v1.1}"

HOST_IP="$(hostname -I | awk '{print $1}')"

HARBOR_PROJECT="platform-images"
IMAGE_NAME="webapp"
NAMESPACE="container-platform"

HARBOR_PASSWORD="$(
  awk '/^harbor_admin_password:/ {
      sub(/^[^:]*:[[:space:]]*/, "");
      print;
      exit
  }' "$HOME/harbor/harbor.yml"
)"

echo "============================================"
echo "Deploying application version: ${VERSION}"
echo "============================================"

cd "$HOME/container-lab/webapp"

echo
echo "===== BUILD ====="

sudo docker build \
  -t "webapp-optimized:${VERSION}" \
  -f Dockerfile.multistage \
  .


echo
echo "===== TAG ====="

sudo docker tag \
  "webapp-optimized:${VERSION}" \
  "${HOST_IP}/${HARBOR_PROJECT}/${IMAGE_NAME}:${VERSION}"


echo
echo "===== PUSH ====="

sudo docker push \
  "${HOST_IP}/${HARBOR_PROJECT}/${IMAGE_NAME}:${VERSION}"


echo
echo "===== UPDATE KUBERNETES DEPLOYMENT ====="

kubectl set image \
  deployment/webapp \
  webapp="host.minikube.internal:80/${HARBOR_PROJECT}/${IMAGE_NAME}:${VERSION}" \
  -n "${NAMESPACE}"


echo
echo "===== WAIT FOR ROLLOUT ====="

kubectl rollout status \
  deployment/webapp \
  -n "${NAMESPACE}" \
  --timeout=300s


echo
echo "===== DEPLOYED IMAGE ====="

kubectl get deployment webapp \
  -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

echo

echo "Deployment completed successfully."
