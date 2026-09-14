#!/bin/bash

echo "Performance Impact Analysis"
echo "==========================="

echo
echo "1. Response Time Analysis"

for port in {9001..9005}; do
    echo "Testing port $port:"
    curl -s -o /dev/null \
      -w 'HTTP %{http_code} | Time %{time_total}s\n' \
      "http://localhost:$port"
done

echo
echo "2. Concurrent Request Handling"
echo "Sending 50 requests to load balancer..."

START=$(date +%s%N)

for i in {1..50}; do
    curl -s http://localhost >/dev/null &
done

wait

END=$(date +%s%N)
ELAPSED=$(( (END - START) / 1000000 ))

echo "Completed 50 requests in ${ELAPSED} ms"

echo
echo "3. Resource Utilization"

sudo docker stats --no-stream \
  web-app-instance-1 \
  web-app-instance-2 \
  web-app-instance-3 \
  web-app-instance-4 \
  web-app-instance-5
