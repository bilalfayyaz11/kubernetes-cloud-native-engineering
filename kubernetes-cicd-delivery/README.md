# Kubernetes CI/CD Delivery Pipeline

## Overview

This implementation demonstrates a container delivery workflow integrating GitHub Actions, Docker, Kubernetes, automated health verification, deployment rollback, and environment-specific Kustomize configuration.

The pipeline separates CI responsibilities from deployment access:

~~text
Developer
   |
   v
Git Push
   |
   v
GitHub Actions
   |
   +--> Test
   |
   +--> Dependency Audit
   |
   +--> Docker Build
   |
   +--> Container Registry
              |
              v
        Self-Hosted Runner
              |
              v
           kubectl
              |
              v
        Kubernetes Cluster
~~

A self-hosted deployment runner is used because private Kubernetes environments such as Minikube are generally not reachable directly from GitHub-hosted runners.

## Application

The repository contains a small Node.js HTTP service.

Endpoints:

~~text
GET /
GET /health
~~

The root endpoint returns application version information.

The health endpoint supports Kubernetes readiness and liveness probes.

## Container Build

The application uses a minimal Node.js Alpine image and runs as the non-root `node` user.

Build locally:

~~bash
docker build -t cicd-app:local .
~~

Run:

~~bash
docker run --rm \
  -p 3000:3000 \
  cicd-app:local
~~

Verify:

~~bash
curl http://localhost:3000/
curl http://localhost:3000/health
~~

## Kubernetes Architecture

~~text
cicd-app-service
      |
      v
cicd-app Deployment
      |
      +--> Pod
      +--> Pod
      +--> Pod
~~

The workload includes:

- readiness probe
- liveness probe
- CPU requests and limits
- memory requests and limits
- multiple replicas
- immutable container image support

## CI Pipeline

The GitHub-hosted CI stages perform:

1. dependency installation
2. automated testing
3. dependency security audit
4. Docker image build
5. image publication

Each release image is tagged using the Git commit SHA.

Example:

~~text
docker.io/USERNAME/cicd-app:f93b4a2...
~~

Using immutable identifiers makes deployed versions traceable back to source control.

## CD Pipeline

Deployment runs on a self-hosted runner with Kubernetes access.

Required runner labels:

~~text
self-hosted
linux
kubernetes
~~

The deployment stage:

1. verifies cluster access
2. applies Kubernetes resources
3. updates the container image
4. records the commit-derived version
5. waits for rollout completion
6. verifies the running Pods
7. executes an application health check

## Required Repository Secrets

GitHub Actions requires:

~~text
DOCKER_USERNAME
DOCKER_TOKEN
~~

Credentials are not stored in this repository.

The Kubernetes kubeconfig should remain on the deployment runner rather than being committed to Git.

## Rollback

A manually triggered rollback workflow is included.

GitHub Actions:

~~text
Actions
  |
  v
Rollback Deployment
  |
  v
Run workflow
~~

An optional deployment revision can be supplied.

Without one, Kubernetes restores the previous revision.

The workflow then verifies rollout completion and executes an application health check.

## Manual Rollback

View revision history:

~~bash
kubectl rollout history deployment/cicd-app
~~

Rollback:

~~bash
kubectl rollout undo deployment/cicd-app
~~

Verify:

~~bash
kubectl rollout status deployment/cicd-app

kubectl get pods \
  -l app=cicd-app
~~

## Failure Recovery Demonstrated

The deployment workflow was validated using an intentionally unhealthy release.

~~text
Healthy release
      |
      v
New release
      |
      v
Health checks fail
      |
      v
Rollout does not complete
      |
      v
Rollback
      |
      v
Previous healthy revision restored
~~

This demonstrates Kubernetes Deployment revision history and recovery behavior.

## Environment Configuration

Kustomize overlays are provided for:

~~text
staging
production
~~

Render staging:

~~bash
kubectl kustomize \
  k8s/environments/staging
~~

Render production:

~~bash
kubectl kustomize \
  k8s/environments/production
~~

Staging uses a smaller replica count while production uses multiple replicas.

## Apply an Environment

Create the namespaces first:

~~bash
kubectl create namespace staging
kubectl create namespace production
~~

Deploy staging:

~~bash
kubectl apply \
  -k k8s/environments/staging
~~

Deploy production:

~~bash
kubectl apply \
  -k k8s/environments/production
~~

## Observability and Troubleshooting

Inspect rollout history:

~~bash
kubectl rollout history deployment/cicd-app
~~

Inspect Pods:

~~bash
kubectl get pods \
  -l app=cicd-app \
  -o wide
~~

Check events:

~~bash
kubectl get events \
  --sort-by=.metadata.creationTimestamp
~~

Inspect a failed deployment:

~~bash
kubectl describe deployment cicd-app

kubectl describe pods \
  -l app=cicd-app
~~

View logs:

~~bash
kubectl logs \
  -l app=cicd-app \
  --tail=100 \
  --prefix=true
~~

## Security Considerations

The pipeline avoids committing:

- Docker credentials
- registry tokens
- kubeconfig files
- environment secrets

For production environments, recommended improvements include:

- OpenID Connect for cloud authentication
- short-lived credentials
- container vulnerability scanning
- image signing
- admission policy enforcement
- protected GitHub environments
- approval gates
- least-privilege Kubernetes ServiceAccounts
- GitOps reconciliation

## Production Improvements

A production-grade evolution could add:

- Argo CD or Flux
- Helm
- SBOM generation
- Trivy or Grype scanning
- Cosign image signing
- policy-as-code
- progressive delivery
- canary releases
- deployment approval gates
- artifact provenance
- Prometheus/Grafana monitoring

## Skills Demonstrated

- GitHub Actions
- CI/CD architecture
- Docker
- Kubernetes Deployments
- Kubernetes Services
- health probes
- immutable image tagging
- automated deployment verification
- Kubernetes rollback
- Kustomize
- staging/production environment separation
- self-hosted runners
- release failure recovery
