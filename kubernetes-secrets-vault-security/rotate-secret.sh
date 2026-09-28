#!/bin/bash
set -euo pipefail

SECRET_NAME="user-credentials"

NEW_PASSWORD="$(
  openssl rand -base64 32 \
  | tr -d '\n'
)"

ENCODED_PASSWORD="$(
  printf '%s' "$NEW_PASSWORD" \
  | base64 -w 0
)"

kubectl patch secret "$SECRET_NAME" \
  --type=merge \
  -p="{\"data\":{\"password\":\"${ENCODED_PASSWORD}\"}}" \
  >/dev/null

unset NEW_PASSWORD
unset ENCODED_PASSWORD

echo "PASS: user-credentials password rotated"
echo "New password value intentionally not displayed"
