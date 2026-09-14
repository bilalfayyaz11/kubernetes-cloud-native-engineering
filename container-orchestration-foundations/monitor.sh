#!/bin/bash

echo "Container Resource Monitoring"
echo "============================="

while true; do
    echo
    echo "Timestamp: $(date)"
    echo

    echo "Container Status:"
    sudo docker ps --format \
'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

    echo
    echo "Resource Usage:"
    sudo docker stats --no-stream --format \
'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}'

    sleep 5
done
