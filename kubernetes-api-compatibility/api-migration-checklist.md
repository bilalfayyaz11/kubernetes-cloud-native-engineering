# Kubernetes API Migration Checklist

## Pre-Migration Assessment

- [ ] Inventory Kubernetes manifests and Helm/Kustomize output.
- [ ] Extract all `apiVersion` references.
- [ ] Identify removed or deprecated APIs.
- [ ] Record current Kubernetes server version.
- [ ] Confirm target Kubernetes version.
- [ ] Review API structural changes.
- [ ] Identify admission-control or policy replacements.
- [ ] Determine whether controllers or CRDs depend on affected APIs.
- [ ] Prepare rollback and recovery steps.
- [ ] Test changes outside production first.

## Manifest Migration

- [ ] Replace removed Deployment APIs with `apps/v1`.
- [ ] Confirm Deployment selectors explicitly match Pod template labels.
- [ ] Replace removed Ingress APIs with `networking.k8s.io/v1`.
- [ ] Add required Ingress `pathType`.
- [ ] Convert legacy `serviceName` to `backend.service.name`.
- [ ] Convert legacy `servicePort` to `backend.service.port`.
- [ ] Replace PodSecurityPolicy with an appropriate Pod Security Admission strategy.
- [ ] Review workload security contexts against the chosen Pod Security Standard.
- [ ] Update documentation and deployment automation.

## Validation

- [ ] Run local/static deprecation scan.
- [ ] Run `kubectl apply --dry-run=client`.
- [ ] Run `kubectl apply --dry-run=server`.
- [ ] Confirm target API versions are served by the cluster.
- [ ] Deploy migrated resources into a validation namespace.
- [ ] Verify rollout health.
- [ ] Verify Service connectivity.
- [ ] Verify Ingress resource structure.
- [ ] Verify admission-policy behavior.
- [ ] Confirm privileged/non-compliant workloads are denied where expected.
- [ ] Confirm compliant workloads are admitted.

## Production Readiness

- [ ] Capture before/after API inventory.
- [ ] Review Kubernetes release deprecation notes before cluster upgrade.
- [ ] Scan manifests in CI before merge.
- [ ] Block known removed API versions in pipelines.
- [ ] Test migration against the target cluster version.
- [ ] Confirm monitoring and alerting are in place.
- [ ] Record migration evidence and rollback procedure.

## Post-Migration Verification

- [ ] Confirm all workloads are healthy.
- [ ] Confirm removed APIs are absent from committed manifests.
- [ ] Confirm deprecated APIs are not served where expected.
- [ ] Review application logs and Kubernetes events.
- [ ] Verify admission controls.
- [ ] Re-run API compatibility scan.
- [ ] Update runbooks.
- [ ] Schedule recurring compatibility checks.

## Common Migration Patterns

### Deployment

Legacy:

    extensions/v1beta1

Current:

    apps/v1

Key requirement:

    spec.selector must explicitly match template labels.

### Ingress

Legacy:

    extensions/v1beta1

Current:

    networking.k8s.io/v1

Key changes:

    serviceName
        ->
    backend.service.name

    servicePort
        ->
    backend.service.port.number

    pathType
        ->
    required field

### PodSecurityPolicy

Legacy:

    policy/v1beta1 PodSecurityPolicy

Replacement:

    Pod Security Admission using namespace labels

Common levels:

    privileged
    baseline
    restricted
