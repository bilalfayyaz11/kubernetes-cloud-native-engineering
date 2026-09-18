# Kubernetes NetworkPolicy Troubleshooting

## 1. Confirm the CNI Enforces NetworkPolicy

Creating a NetworkPolicy object does not guarantee enforcement.

The cluster must use a compatible network plugin such as:

    Calico
    Cilium
    Antrea

This implementation uses Calico.

## 2. Check Policy Selection

A policy only affects Pods matched by:

    spec.podSelector

Inspect labels with:

    kubectl get pods --show-labels

## 3. Understand Isolation

A Pod becomes isolated for ingress when at least one NetworkPolicy selects it with:

    policyTypes:
      - Ingress

Likewise, egress isolation starts when a selecting policy contains:

    policyTypes:
      - Egress

## 4. Policies Are Additive

NetworkPolicies are not evaluated as ordered firewall rules.

Allowed traffic is the union of all applicable policy rules.

Therefore:

    default deny
        +
    frontend allow

results in:

    frontend allowed
    unrelated sources blocked

## 5. Pod Selector Scope

A standalone podSelector inside an ingress peer selects Pods from the NetworkPolicy's namespace.

Example:

    from:
      - podSelector:
          matchLabels:
            app: frontend

## 6. Namespace Selector

A namespaceSelector selects namespaces using namespace labels.

Example:

    namespaceSelector:
      matchLabels:
        access-zone: trusted

## 7. Combined Namespace + Pod Selector

When namespaceSelector and podSelector appear in the same peer entry, both conditions must match.

This is useful for restricting traffic to a specific class of Pods inside approved namespaces.

## 8. DNS Under Egress Isolation

A default-deny or restrictive egress policy can accidentally break DNS.

DNS must be explicitly allowed when required.

This implementation permits:

    UDP/53
    TCP/53

to CoreDNS in kube-system.

## 9. Useful Diagnostic Sequence

    Verify Pod health
        |
        v
    Inspect Pod labels
        |
        v
    Inspect NetworkPolicy selectors
        |
        v
    Inspect namespace labels
        |
        v
    Check Service / EndpointSlice
        |
        v
    Test direct TCP connectivity
        |
        v
    Verify DNS separately
        |
        v
    Inspect CNI components

## 10. No Violation Event Is Not Proof of Failure

Standard Kubernetes does not require blocked packets to produce a Kubernetes Event.

Connectivity testing and CNI-specific observability are usually more reliable evidence.

## Security Model

The final segmentation model is:

    frontend
       |
       | TCP/5432
       v
    backend
       X
       X test-client
       X external-client

Backend egress:

    backend
       |
       +--> frontend:80
       |
       +--> CoreDNS:53
       |
       X--> external namespace web service
