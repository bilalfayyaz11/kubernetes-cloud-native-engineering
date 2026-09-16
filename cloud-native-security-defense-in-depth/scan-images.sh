#!/usr/bin/env bash

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

scan_image() {
    local image="$1"
    local report
    local count

    report="$(mktemp)"

    echo -e "${YELLOW}Scanning: ${image}${NC}"

    if ! sudo trivy image \
        --quiet \
        --severity HIGH,CRITICAL \
        --format json \
        --output "$report" \
        "$image"; then

        echo -e "${RED}✗ Trivy scan failed${NC}"
        rm -f "$report"
        return 2
    fi

    count="$(
        jq '
        [
          .Results[]?
          | .Vulnerabilities[]?
          | select(.Severity == "HIGH" or .Severity == "CRITICAL")
        ]
        | length
        ' "$report"
    )"

    rm -f "$report"

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}✓ No HIGH/CRITICAL vulnerabilities found${NC}"
        return 0
    fi

    echo -e "${RED}✗ Found ${count} HIGH/CRITICAL vulnerabilities${NC}"
    return 1
}

images=(
    "nodegoat:vulnerable"
    "nodegoat:secure"
    "nginxinc/nginx-unprivileged:alpine"
)

overall_status=0

for image in "${images[@]}"; do
    scan_image "$image" || overall_status=1
    echo "----------------------------------------"
done

exit "$overall_status"
