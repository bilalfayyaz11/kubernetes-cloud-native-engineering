#!/bin/bash

echo "Testing all application instances..."
echo "===================================="

for port in {9001..9005}; do
    response=$(curl -s -o /dev/null -w "%{http_code}" \
      "http://localhost:$port")

    if [ "$response" = "200" ]; then
        echo "Port $port: OK"
    else
        echo "Port $port: FAILED (HTTP $response)"
    fi
done
