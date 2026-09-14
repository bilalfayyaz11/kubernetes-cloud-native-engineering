#!/bin/bash

APP_NAME="web-app"
BASE_PORT=9000
INSTANCES=5

echo "Manually scaling $APP_NAME to $INSTANCES instances..."

for i in $(seq 1 $INSTANCES); do
    PORT=$((BASE_PORT + i))
    CONTAINER_NAME="${APP_NAME}-instance-${i}"

    echo "Deploying $CONTAINER_NAME on port $PORT"

    sudo docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    sudo docker run -d \
      --name "$CONTAINER_NAME" \
      -p "$PORT:80" \
      nginx:latest

    if [ $? -eq 0 ]; then
        echo "SUCCESS: $CONTAINER_NAME deployed"
    else
        echo "FAILED: $CONTAINER_NAME"
    fi
done

echo
echo "Scaling complete."
sudo docker ps --filter "name=web-app-instance" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
