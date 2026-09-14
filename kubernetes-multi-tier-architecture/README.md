# Kubernetes Multi-Tier Application

## Overview

This implementation deploys a three-tier application on Kubernetes with independently managed frontend, backend, and database components.

The architecture demonstrates internal service discovery, configuration externalization, credential separation, health probes, horizontal scaling, and end-to-end service communication.

## Architecture

~~text
External Client
      │
      ▼
frontend-service
    NodePort
      │
      ▼
┌──────────────────┐
│   Nginx Frontend │
│    3 replicas    │
└────────┬─────────┘
         │ /api/
         ▼
 backend-service
   ClusterIP
         │
         ▼
┌──────────────────┐
│    Flask API     │
│    2 replicas    │
└────────┬─────────┘
         │ TCP 3306
         ▼
database-service
   ClusterIP
         │
         ▼
┌──────────────────┐
│      MySQL       │
│     1 replica    │
└──────────────────┘
~~

## Components

### Frontend

Nginx serves static content and proxies `/api/` requests to the backend service.

Key characteristics:

- 3 replicas
- NodePort exposure
- readiness probe
- liveness probe
- nginx reverse proxy
- ConfigMap-mounted HTML

### Backend

A Flask API exposes:

~~text
/api/health
/api/data
~~

The backend resolves `database-service` using Kubernetes DNS and queries MySQL over TCP port `3306`.

Key characteristics:

- 2 replicas
- internal ClusterIP
- ConfigMap-driven configuration
- Secret-driven database credential
- health probes
- database connection retry logic

### Database

MySQL runs behind an internal ClusterIP Service.

Configuration is separated into:

- non-sensitive values → ConfigMap
- credentials → Secret

The example manifest intentionally uses `emptyDir`, so database data is ephemeral and is not presented as production-grade persistent storage.

## Deploy

Create the namespace:

~~bash
kubectl apply -f namespace.yaml
~~

Create credentials from the example:

~~bash
cp database-secret.example.yaml database-secret.yaml

# Edit CHANGE_ME values before applying.
kubectl apply -f database-secret.yaml
~~

Apply database resources:

~~bash
kubectl apply -f database-config.yaml
kubectl apply -f database-deployment.yaml
kubectl apply -f database-service.yaml
~~

Apply backend resources:

~~bash
kubectl apply -f backend-config.yaml
kubectl apply -f backend-app.yaml
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
~~

Apply frontend resources:

~~bash
kubectl apply -f frontend-html.yaml
kubectl apply -f nginx-config.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml
~~

## Verify Deployment State

~~bash
kubectl get deployments,pods,services \
  -n multi-tier-app
~~

Expected application structure:

~~text
database   1 replica
backend    2 replicas
frontend   3 replicas
~~

## Verify Service Discovery

Check backend DNS from a frontend Pod:

~~bash
FRONTEND_POD=$(kubectl get pods \
  -n multi-tier-app \
  -l tier=frontend \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec \
  -n multi-tier-app \
  "$FRONTEND_POD" \
  -- getent hosts backend-service
~~

Check database DNS from a backend Pod:

~~bash
BACKEND_POD=$(kubectl get pods \
  -n multi-tier-app \
  -l tier=backend \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec \
  -n multi-tier-app \
  "$BACKEND_POD" \
  -- python -c \
  'import socket; print(socket.gethostbyname("database-service"))'
~~

## End-to-End Validation

Test the backend health endpoint through nginx:

~~bash
kubectl run health-test \
  -n multi-tier-app \
  --image=curlimages/curl \
  --restart=Never \
  --rm -i \
  -- curl -fsS \
  http://frontend-service/api/health
~~

Expected result:

~~json
{"service":"backend","status":"healthy"}
~~

Test the complete chain:

~~bash
kubectl run data-test \
  -n multi-tier-app \
  --image=curlimages/curl \
  --restart=Never \
  --rm -i \
  -- curl -fsS \
  http://frontend-service/api/data
~~

This request follows:

~~text
Client
  ↓
frontend-service
  ↓
Nginx
  ↓
backend-service
  ↓
Flask
  ↓
database-service
  ↓
MySQL
~~

A successful response confirms application-level communication across all three tiers.

## Scaling

Scale the frontend independently:

~~bash
kubectl scale deployment frontend \
  -n multi-tier-app \
  --replicas=5
~~

Scale the backend independently:

~~bash
kubectl scale deployment backend \
  -n multi-tier-app \
  --replicas=3
~~

Kubernetes Services continue routing traffic to available endpoints as replica membership changes.

## Configuration Management

Non-sensitive application configuration is stored in ConfigMaps:

- `database-config`
- `backend-config`
- `backend-app-code`
- `frontend-html`
- `nginx-config`

Sensitive credentials are referenced from:

~~text
database-secret
~~

The real Secret manifest is intentionally excluded from version control.

## Health Management

Frontend and backend workloads use readiness and liveness probes.

Readiness prevents traffic from being sent to containers that are not prepared to serve requests.

Liveness allows Kubernetes to detect and restart unhealthy containers.

## Troubleshooting

### Backend cannot reach MySQL

~~bash
kubectl get endpoints database-service \
  -n multi-tier-app

kubectl logs \
  -n multi-tier-app \
  -l tier=database

kubectl logs \
  -n multi-tier-app \
  -l tier=backend
~~

Verify DNS:

~~bash
kubectl exec \
  -n multi-tier-app \
  "$BACKEND_POD" \
  -- python -c \
  'import socket; print(socket.gethostbyname("database-service"))'
~~

### Frontend cannot reach backend

Check service endpoints:

~~bash
kubectl get endpoints backend-service \
  -n multi-tier-app
~~

Inspect nginx:

~~bash
kubectl get configmap nginx-config \
  -n multi-tier-app \
  -o yaml
~~

### Service has no endpoints

Compare:

~~bash
kubectl get pods \
  -n multi-tier-app \
  --show-labels

kubectl describe service <service-name> \
  -n multi-tier-app
~~

A selector mismatch is a common cause.

## Security Notes

Kubernetes Services provide logical routing boundaries but do not, by themselves, restrict network access.

Although MySQL is exposed only through an internal ClusterIP, any permitted Pod in the cluster network may still be able to reach it.

Production deployments should add NetworkPolicies to explicitly restrict database access to authorized backend workloads.

Secrets should also be integrated with an appropriate external secret-management system for higher-assurance environments.

## Production Improvements

For a production implementation:

- replace MySQL `emptyDir` with persistent storage
- build the Flask dependencies into a container image rather than installing them at startup
- use immutable/versioned images
- add NetworkPolicies
- use Ingress or Gateway API instead of NodePort
- implement TLS
- use external secret management
- add observability and metrics
- define PodDisruptionBudgets
- configure horizontal autoscaling
- add database backup and recovery

## Skills Demonstrated

- Multi-tier Kubernetes architecture
- Kubernetes Deployments
- ClusterIP and NodePort Services
- internal service discovery
- DNS-based communication
- ConfigMaps
- Secrets
- nginx reverse proxying
- Flask API deployment
- MySQL connectivity
- readiness and liveness probes
- horizontal scaling
- service endpoint validation
- application troubleshooting
- end-to-end distributed-system testing
