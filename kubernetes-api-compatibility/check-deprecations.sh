#!/bin/bash
set -e

echo "=================================================="
echo " API DEPRECATION SCAN"
echo "=================================================="

FOUND=0

for file in *.yaml; do
    [ -f "$file" ] || continue

    echo
    echo "Analyzing: $file"

    while IFS= read -r line; do
        echo "  $line"

        case "$line" in
            *extensions/v1beta1*)
                echo "  WARNING: removed API extensions/v1beta1"
                FOUND=1
                ;;
            *policy/v1beta1*)
                echo "  WARNING: removed API policy/v1beta1"
                FOUND=1
                ;;
        esac
    done < <(grep -n 'apiVersion:' "$file" || true)
done

echo
if [ "$FOUND" -eq 1 ]; then
    echo "RESULT: deprecated/removed APIs detected."
else
    echo "RESULT: no known removed APIs detected."
fi
