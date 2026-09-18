# Kubernetes Ingress NetworkPolicy Model

## Baseline

Without a NetworkPolicy selecting the backend Pod, workloads can initiate connections according to the cluster's normal networking behavior.

## Isolation

The backend is selected by:

    podSelector:
      matchLabels:
        app: backend

A policy with:

    policyTypes:
      - Ingress

and no ingress rules isolates the selected Pod from incoming traffic.

## Selective Pod Access

The frontend allow policy permits:

    app: frontend
        |
        | TCP/5432
        v
    app: backend

Other Pods are not permitted by that rule.

## Namespace-Based Access

The trusted namespace policy permits traffic from namespaces labeled:

    access-zone: trusted

The external namespace is labeled:

    access-zone: untrusted

and therefore remains outside the permitted namespace set.

## Additive Behavior

Kubernetes NetworkPolicies are additive.

If several policies select the same Pod, the allowed traffic is the union of what those policies permit.

A deny policy does not override an allow policy in firewall-rule order.

Instead:

    selected Pod
       |
       v
    isolated for ingress
       |
       v
    union of allowed ingress rules

## Important Selector Semantics

This form:

    from:
      - namespaceSelector: ...

matches Pods from namespaces matching the namespace selector.

This form:

    from:
      - podSelector: ...

matches Pods in the same namespace as the NetworkPolicy unless combined with a namespace selector in the same peer.

## Security Outcome

NetworkPolicy enables application-tier microsegmentation.

Instead of:

    any workload -> backend database

the environment can enforce:

    approved source -> backend database

while rejecting unrelated traffic.
