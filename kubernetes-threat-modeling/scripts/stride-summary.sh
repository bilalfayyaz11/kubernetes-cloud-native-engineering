#!/usr/bin/env bash

set -u

REGISTER="${1:-models/final-risk-register.csv}"

if [ ! -f "$REGISTER" ]; then
  echo "ERROR: risk register missing"
  exit 1
fi

echo "===== STRIDE THREAT SUMMARY ====="

echo
echo "Total threats:"
tail -n +2 "$REGISTER" | wc -l

echo
echo "Priority distribution:"
tail -n +2 "$REGISTER" \
  | cut -d, -f8 \
  | sort \
  | uniq -c \
  | sort -nr

echo
echo "STRIDE distribution:"
tail -n +2 "$REGISTER" \
  | cut -d, -f2 \
  | sort \
  | uniq -c \
  | sort -nr

echo
echo "High and Critical threats:"
awk -F, '
NR > 1 && ($8 == "High" || $8 == "Critical") {
  printf "%s | %s | %s | %s\n", $1, $2, $3, $4
}
' "$REGISTER"
