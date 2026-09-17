#!/usr/bin/env bash

set -u

CLUSTER="${CLUSTER:-data-protection}"
NODE="${CLUSTER}-control-plane"

ENDPOINT="http://127.0.0.1:23790"

echo "===== RECOVERY VALIDATION ====="

echo
echo "Restored etcd health:"

docker exec \
  "$NODE" \
  sh -c "
    ETCDCTL_API=3 \
    etcdctl \
      --endpoints=${ENDPOINT} \
      endpoint health
  "

echo
echo "Recovery marker:"

if docker exec \
  "$NODE" \
  sh -c "
    ETCDCTL_API=3 \
    etcdctl \
      --endpoints=${ENDPOINT} \
      get \
      /registry/configmaps/recovery-validation/recovery-marker \
      --print-value-only
  " \
  | grep -aq PRE_INCIDENT_STATE
then
  echo "PASS: pre-incident marker recovered"
else
  echo "FAIL: marker not recovered"
fi

echo
echo "Recovery workload:"

if docker exec \
  "$NODE" \
  sh -c "
    ETCDCTL_API=3 \
    etcdctl \
      --endpoints=${ENDPOINT} \
      get \
      /registry/deployments/recovery-validation/recovery-workload \
      --print-value-only
  " \
  | grep -aq recovery-workload
then
  echo "PASS: pre-incident Deployment recovered"
else
  echo "FAIL: Deployment not recovered"
fi

echo
echo "Post-backup object:"

POST_BACKUP=$(
  docker exec \
    "$NODE" \
    sh -c "
      ETCDCTL_API=3 \
      etcdctl \
        --endpoints=${ENDPOINT} \
        get \
        /registry/configmaps/recovery-validation/post-backup-only \
        --print-value-only
    " \
  2>/dev/null
)

if [ -z "$POST_BACKUP" ]; then
  echo "PASS: post-backup object absent"
else
  echo "FAIL: post-backup object unexpectedly present"
fi
