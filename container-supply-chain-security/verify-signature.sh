#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <image-reference> <public-key>"
  exit 2
fi

IMAGE="$1"
PUBLIC_KEY="$2"

if cosign verify \
  --allow-insecure-registry \
  --key "$PUBLIC_KEY" \
  "$IMAGE" \
  >/dev/null 2>&1; then

  echo "PASS: signature valid for $IMAGE"
  exit 0

else

  echo "FAIL: signature verification failed for $IMAGE"
  exit 1
fi
