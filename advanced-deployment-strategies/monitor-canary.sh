#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="deployment-strategies"
REQUESTS="${1:-100}"
LOCAL_PORT="${2:-8080}"

V1=0
V3=0
FAILED=0
OTHER=0

echo "Sampling ${REQUESTS} requests..."

for i in $(seq 1 "$REQUESTS"); do

    RESPONSE="$(
      curl -sS \
        --max-time 3 \
        -H 'Connection: close' \
        "http://localhost:${LOCAL_PORT}/" \
      || true
    )"

    if echo "$RESPONSE" | grep -q 'Version 1.0'; then
        V1=$((V1 + 1))

    elif echo "$RESPONSE" | grep -q 'Version 3.0'; then
        V3=$((V3 + 1))

    elif [ -z "$RESPONSE" ]; then
        FAILED=$((FAILED + 1))

    else
        OTHER=$((OTHER + 1))
    fi

done

SUCCESSFUL=$((V1 + V3))

echo
echo "Results:"
echo "  v1 stable : $V1"
echo "  v3 canary : $V3"
echo "  other     : $OTHER"
echo "  failed    : $FAILED"

if [ "$SUCCESSFUL" -gt 0 ]; then

    V1_PCT=$((V1 * 100 / SUCCESSFUL))
    V3_PCT=$((V3 * 100 / SUCCESSFUL))

    echo
    echo "Observed distribution:"
    echo "  v1 stable : ${V1_PCT}%"
    echo "  v3 canary : ${V3_PCT}%"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: one or more requests failed."
    exit 1
fi
