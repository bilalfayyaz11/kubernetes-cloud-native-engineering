#!/bin/bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="${WORKDIR}/deprecation-alert-report.txt"

: > "$REPORT"

log() {
    echo "$1" | tee -a "$REPORT"
}

log "KUBERNETES DEPRECATION ALERT REPORT"
log "Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
log ""

ALERTS=0

check_api() {
    local api="$1"

    if kubectl api-versions | grep -qx "$api"; then
        log "ALERT: deprecated/legacy API still served: $api"
        ALERTS=$((ALERTS + 1))
    else
        log "OK: API not served: $api"
    fi
}

check_manifest_pattern() {
    local pattern="$1"
    local description="$2"

    if grep -RniE \
      "$pattern" \
      current-manifests \
      --include='*.yaml' \
      --include='*.yml' \
      >/tmp/deprecation-pattern.txt 2>/dev/null
    then
        log "ALERT: $description found in migrated manifests"
        cat /tmp/deprecation-pattern.txt | tee -a "$REPORT"
        ALERTS=$((ALERTS + 1))
    else
        log "OK: $description absent from migrated manifests"
    fi
}

log ""
log "===== API SERVER CHECKS ====="

check_api "extensions/v1beta1"
check_api "policy/v1beta1"
check_api "networking.k8s.io/v1beta1"

log ""
log "===== MIGRATED MANIFEST CHECKS ====="

check_manifest_pattern \
  'apiVersion:[[:space:]]*extensions/v1beta1' \
  'extensions/v1beta1'

check_manifest_pattern \
  'apiVersion:[[:space:]]*policy/v1beta1' \
  'policy/v1beta1'

check_manifest_pattern \
  'apiVersion:[[:space:]]*networking.k8s.io/v1beta1' \
  'networking.k8s.io/v1beta1'

log ""
log "===== RESULT ====="

if [ "$ALERTS" -gt 0 ]; then
    log "ALERTS: $ALERTS"
    exit 1
fi

log "ALERTS: 0"
log "Current migrated manifests passed configured deprecation checks."
