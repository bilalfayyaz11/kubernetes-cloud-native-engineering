#!/usr/bin/env bash
set -euo pipefail

cat > openssl-san.cnf <<'CONF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = myapps.local
O = myapps.local

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = myapps.local
DNS.2 = api.myapps.local
CONF

openssl genrsa -out tls.key 2048

openssl req \
  -x509 \
  -new \
  -nodes \
  -key tls.key \
  -sha256 \
  -days 365 \
  -out tls.crt \
  -config openssl-san.cnf

kubectl create secret tls myapps-tls-secret \
  --cert=tls.crt \
  --key=tls.key \
  -n web-apps \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

rm -f tls.key tls.crt openssl-san.cnf
