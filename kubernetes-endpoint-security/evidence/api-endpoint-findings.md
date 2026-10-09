# Kubernetes API Endpoint Security Findings

## Environment

- Platform: Amazon EC2
- Node private address: 172.31.10.122
- Administrative source address: 202.47.51.242

## API Exposure

The Kubernetes API server listens on TCP 6443.

Access control is enforced at the host firewall layer using a dedicated chain:

`K8S_API_GUARD`

## Trusted Sources

Allowed sources include:

- loopback traffic
- established/related connections
- the node VPC range
- the current administrative source IP

Other TCP/6443 traffic is dropped.

## Cluster Validation

After applying the firewall:

- kubectl access remained functional
- the node remained Ready
- in-cluster access to the Kubernetes API remained functional

## Cloud Metadata Baseline

The EC2 instance requires IMDSv2 for unauthenticated metadata requests.

A Pod-level metadata reachability test was performed without printing metadata values or credentials.

The next stage adds workload-level egress controls that prevent Pods from reaching the metadata endpoint even when network access would otherwise permit it.
