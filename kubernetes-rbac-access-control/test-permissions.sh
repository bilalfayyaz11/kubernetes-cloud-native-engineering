#!/bin/bash
set -u

NAMESPACE="access-control"

WEBAPP="system:serviceaccount:${NAMESPACE}:webapp-service-account"
DATABASE="system:serviceaccount:${NAMESPACE}:database-service-account"

check() {
    local identity="$1"
    local verb="$2"
    local resource="$3"

    kubectl auth can-i \
      "$verb" "$resource" \
      -n "$NAMESPACE" \
      --as="$identity" \
      2>/dev/null || true
}

echo "=================================================="
echo " WEBAPP SERVICEACCOUNT"
echo "=================================================="

echo "Can get pods       : $(check "$WEBAPP" get pods)"
echo "Can list services  : $(check "$WEBAPP" list services)"
echo "Can get configmaps : $(check "$WEBAPP" get configmaps)"
echo "Can get secrets    : $(check "$WEBAPP" get secrets)"
echo "Can create pods    : $(check "$WEBAPP" create pods)"

echo
echo "=================================================="
echo " DATABASE SERVICEACCOUNT"
echo "=================================================="

echo "Can get secrets    : $(check "$DATABASE" get secrets)"
echo "Can get pods       : $(check "$DATABASE" get pods)"
echo "Can get PVCs       : $(check "$DATABASE" get persistentvolumeclaims)"
echo "Can get services   : $(check "$DATABASE" get services)"
echo "Can create pods    : $(check "$DATABASE" create pods)"
