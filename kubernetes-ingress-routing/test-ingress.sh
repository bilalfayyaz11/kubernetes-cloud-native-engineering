#!/usr/bin/env bash
set -euo pipefail

echo "HTTP redirect:"
curl -s -o /dev/null \
  -w 'status=%{http_code} redirect=%{redirect_url}\n' \
  http://myapps.local/app1

echo
echo "App 1:"
curl -k -fsS https://myapps.local/app1 \
  | grep -E '<title>|<h1>'

echo
echo "App 2:"
curl -k -fsS https://myapps.local/app2 \
  | grep -E '<title>|<h1>'

echo
echo "API hostname:"
curl -k -fsS https://api.myapps.local/ \
  | grep -E '<title>|<h1>'

echo
echo "Ingress resources:"
kubectl get ingress -n web-apps

echo
echo "Service endpoints:"
kubectl get endpoints -n web-apps
