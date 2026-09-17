#!/usr/bin/env sh

set -eu

VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_ROLE="${VAULT_ROLE:-myapp-role}"

SA_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"

get_vault_token() {
  jwt="$(cat "$SA_TOKEN_PATH")"

  response="$(
    curl -sS \
      -X POST \
      -H "Content-Type: application/json" \
      -d "{\"jwt\":\"${jwt}\",\"role\":\"${VAULT_ROLE}\"}" \
      "${VAULT_ADDR}/v1/auth/kubernetes/login"
  )"

  token="$(
    echo "$response" \
    | jq -r '.auth.client_token'
  )"

  if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "ERROR: Vault authentication failed" >&2
    exit 1
  fi

  printf '%s' "$token"
}

get_static_secret_metadata() {
  path="$1"
  token="$2"

  curl -sS \
    -H "X-Vault-Token: ${token}" \
    "${VAULT_ADDR}/v1/secret/data/${path}" \
  | jq '{
      path: "'"${path}"'",
      fields: (.data.data | keys),
      version: .data.metadata.version
    }'
}

get_db_credential_metadata() {
  token="$1"

  curl -sS \
    -H "X-Vault-Token: ${token}" \
    "${VAULT_ADDR}/v1/database/creds/my-role" \
  | jq '{
      lease_id,
      lease_duration,
      renewable,
      username: .data.username,
      password: "[REDACTED]"
    }'
}

TOKEN="$(get_vault_token)"

echo "=== Vault Authentication ==="
echo "Authenticated: yes"

echo
echo "=== Static Secret Metadata ==="
get_static_secret_metadata \
  "myapp/database" \
  "$TOKEN"

get_static_secret_metadata \
  "myapp/api" \
  "$TOKEN"

get_static_secret_metadata \
  "myapp/config" \
  "$TOKEN"

echo
echo "=== Dynamic Database Credential Metadata ==="
get_db_credential_metadata \
  "$TOKEN"

unset TOKEN
