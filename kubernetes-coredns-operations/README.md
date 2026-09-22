# Kubernetes CoreDNS Operations and Troubleshooting

## Overview

This implementation demonstrates Kubernetes DNS service discovery, CoreDNS configuration, custom DNS records, controlled failure simulation, troubleshooting, recovery, metrics collection, and DNS load validation.

The environment was created from a fresh Ubuntu host using Kubernetes, containerd, Flannel, and CoreDNS.

The workflow validates the complete DNS operational lifecycle:

- Kubernetes service discovery
- short service-name resolution
- fully qualified service-name resolution
- ClusterIP DNS mapping
- CoreDNS configuration inspection
- custom internal DNS records
- controlled DNS failure simulation
- CoreDNS log analysis
- resolver inspection
- direct DNS querying
- DNS connectivity testing
- CoreDNS recovery
- Prometheus metrics collection
- controlled DNS load generation
- post-load health validation

---

## Architecture

    Kubernetes Cluster
            |
            +-----------------------------+
            |                             |
            v                             v
        CoreDNS                    sample-web-service
      kube-system                       default
            |                             |
       kube-dns                          TCP/80
      UDP/TCP 53                          |
            |                       +-----+-----+
            |                       |           |
            |                       v           v
            |                    nginx       nginx
            |
            +------------------------------------+
                                                 |
                                        DNS Test Clients
                                                 |
                               +-----------------+-----------------+
                               |                                   |
                               v                                   v
                         dns-test-pod                    advanced-dns-test
                         nslookup/wget                    dig/nslookup/nc

---

## Environment

The implementation uses:

    Ubuntu 24.04
    Kubernetes 1.36
    kubeadm
    kubelet
    kubectl
    containerd
    crictl
    Flannel
    CoreDNS
    BusyBox
    Netshoot
    nginx

The host initially contained no active Kubernetes cluster or configured CoreDNS environment.

---

## Kubernetes Cluster Bootstrap

The Kubernetes control plane was initialized using kubeadm and containerd.

System preparation included:

- disabling swap
- loading overlay
- loading br_netfilter
- enabling IPv4 forwarding
- enabling bridge traffic processing
- configuring containerd with systemd cgroups
- installing Kubernetes 1.36 components
- configuring crictl
- initializing a single-node control plane
- installing Flannel
- removing the control-plane scheduling taint
- verifying CoreDNS readiness

A basic DNS lookup against:

    kubernetes.default.svc.cluster.local

was used to verify DNS functionality immediately after cluster initialization.

---

## Kubernetes DNS Service Discovery

A two-replica nginx deployment was exposed through a ClusterIP Service named:

    sample-web-service

The application Service is reachable through both:

    sample-web-service

and:

    sample-web-service.default.svc.cluster.local

The first form relies on Kubernetes DNS search domains.

The second form is the complete Kubernetes service FQDN.

---

## Sample Application

The application consists of two nginx replicas.

    sample-web-app
        replicas: 2
             |
             v
    sample-web-service
        ClusterIP
        TCP/80

The Service selects Pods using:

    app=sample-web-app

EndpointSlices are inspected to verify that the Service has Ready backends before DNS validation begins.

---

## DNS Baseline Validation

Before modifying CoreDNS, a baseline was established.

The following were verified:

    short service name resolution
    service FQDN resolution
    Service IP returned by DNS
    direct CoreDNS query
    HTTP connectivity through DNS
    application endpoint readiness

The expected service FQDN is:

    sample-web-service.default.svc.cluster.local

DNS results are compared against the actual ClusterIP of the Service.

This proves that CoreDNS is returning the expected Kubernetes Service address.

---

## Pod Resolver Inspection

The DNS client Pod is used to inspect:

    /etc/resolv.conf

This exposes:

- the cluster DNS nameserver
- namespace search domains
- svc.cluster.local
- cluster.local
- resolver options

Resolver inspection is an important first step when DNS behavior differs between Kubernetes workloads.

---

## CoreDNS Configuration Backup

Before modifying CoreDNS, the live CoreDNS configuration is captured.

The active ConfigMap and Corefile are backed up before any customization.

This provides a known-good recovery path if a configuration change causes:

- DNS failures
- malformed CoreDNS behavior
- Kubernetes service discovery failure
- unexpected NXDOMAIN responses
- failed CoreDNS rollout

---

## Custom Internal DNS

A custom internal DNS zone is added:

    mycompany.local

Example records include:

    api.mycompany.local
    database.mycompany.local
    cache.mycompany.local

The CoreDNS hosts plugin provides deterministic local mappings.

Example design:

    mycompany.local:53 {
        errors

        hosts {
            <address> api.mycompany.local
            192.168.100.10 database.mycompany.local
            192.168.100.20 cache.mycompany.local
            fallthrough
        }

        cache 30
        reload
    }

The custom configuration is validated while preserving normal Kubernetes service discovery.

---

## Kubernetes CoreDNS Plugin

Native Kubernetes service discovery depends on the CoreDNS kubernetes plugin.

The active Corefile contains a configuration similar to:

    kubernetes cluster.local in-addr.arpa ip6.arpa

This plugin provides authoritative answers for Kubernetes cluster-local names.

A CoreDNS Pod can remain Running and reachable on port 53 while Kubernetes service discovery is still broken if this plugin is missing or misconfigured.

---

## Controlled DNS Failure

A controlled failure is introduced by temporarily removing Kubernetes service-discovery functionality from the CoreDNS configuration.

The DNS server remains reachable, but queries such as:

    sample-web-service.default.svc.cluster.local

return NXDOMAIN.

This intentionally separates:

    DNS server availability

from:

    correct Kubernetes DNS functionality

That distinction is critical during production troubleshooting.

---

## NXDOMAIN Diagnosis

A typical failure response resembles:

    Server: 10.96.0.10
    Address: 10.96.0.10:53

    server can't find sample-web-service.default.svc.cluster.local: NXDOMAIN

NXDOMAIN means the DNS server responded but could not resolve the requested name.

This differs from a DNS timeout.

A timeout usually points toward reachability, availability, CNI, firewall, or NetworkPolicy issues.

---

## Advanced DNS Troubleshooting

An advanced troubleshooting Pod provides additional tools.

The workflow validates:

### Resolver Configuration

    cat /etc/resolv.conf

### Standard DNS Query

    dig sample-web-service.default.svc.cluster.local

### Direct CoreDNS Query

    dig @<coredns-service-ip> sample-web-service.default.svc.cluster.local

### Service Lookup

    nslookup kube-dns.kube-system.svc.cluster.local

### Port 53 Connectivity

    nc -zv <coredns-service-ip> 53

The CoreDNS Service IP is discovered dynamically rather than being hard-coded.

---

## CoreDNS Log Analysis

Finite log captures are used for troubleshooting.

Example:

    kubectl logs \
      -n kube-system \
      -l k8s-app=kube-dns \
      --tail=100

This avoids indefinite log streaming while still capturing evidence relevant to the failure.

---

## Failure Analysis Model

The diagnostic process follows:

    DNS Query Failure
           |
           v
    Check Service
           |
           v
    Check EndpointSlices
           |
           v
    Check CoreDNS Pods
           |
           v
    Check Port 53
           |
           v
    Inspect Resolver
           |
           v
    Test Direct CoreDNS Query
           |
           v
    Inspect Corefile
           |
           v
    Validate Kubernetes Plugin
           |
           v
    Identify Root Cause

---

## CoreDNS Recovery

After the controlled failure, a known-good configuration is restored.

Recovery is validated through:

    CoreDNS deployment healthy
    CoreDNS Pods Running
    Kubernetes plugin restored
    short service name resolves
    service FQDN resolves
    direct CoreDNS query succeeds
    HTTP connectivity succeeds

A recovery is not considered complete simply because CoreDNS Pods are Running.

Functional DNS behavior must also be proven.

---

## DNS Baseline Recovery

Before metrics and load validation, DNS health is rechecked.

If NXDOMAIN is detected, the recovery workflow validates:

1. sample-web-service exists
2. sample-web-app exists
3. the Service has Ready EndpointSlices
4. CoreDNS is healthy
5. the Kubernetes plugin exists
6. the test Pod is Running
7. the service FQDN resolves
8. the short service name resolves
9. direct CoreDNS querying works
10. HTTP connectivity through service DNS works

This prevents performance testing against an already broken DNS baseline.

---

## CoreDNS Metrics

CoreDNS exposes Prometheus metrics through:

    prometheus :9153

A temporary port-forward is used to access the metrics endpoint.

Example metric families include:

    coredns_dns_requests_total
    coredns_dns_responses_total

Metrics are captured before and after the DNS load test.

The temporary port-forward is stopped explicitly after metric collection.

---

## Controlled DNS Load Test

A finite workload performs:

    100 DNS queries

against:

    sample-web-service.default.svc.cluster.local

The workload records:

    DNS_LOAD_PASS
    DNS_LOAD_FAIL

The expected result is:

    DNS_LOAD_PASS=100
    DNS_LOAD_FAIL=0

The workload terminates after the fixed number of queries rather than running continuously.

---

## Post-Load Validation

After the load test, the following are verified again:

- CoreDNS deployment health
- CoreDNS Pod health
- Kubernetes service FQDN
- short service name
- HTTP application connectivity
- custom DNS functionality
- CoreDNS metrics
- CoreDNS logs

This proves that service discovery remains operational after the controlled query load.

---

## Troubleshooting Decision Tree

    DNS Failure
        |
        v
    Does Service Exist?
        |
        +-- No --> Correct Service configuration
        |
        v
    Are Endpoints Ready?
        |
        +-- No --> Fix workload or selector
        |
        v
    Is CoreDNS Running?
        |
        +-- No --> Inspect deployment and Pods
        |
        v
    Is Port 53 Reachable?
        |
        +-- No --> Inspect networking or policy
        |
        v
    NXDOMAIN or Timeout?
        |
        +-- NXDOMAIN
        |      |
        |      v
        |   Inspect queried name,
        |   namespace and Corefile
        |
        +-- Timeout
               |
               v
           Inspect DNS availability,
           CNI and traffic restrictions

---

## NXDOMAIN vs Timeout

### NXDOMAIN

Common causes include:

- wrong Service name
- wrong namespace
- Service does not exist
- Kubernetes CoreDNS plugin missing
- incorrect cluster DNS configuration

The DNS server itself is normally reachable.

### Timeout

Common causes include:

- CoreDNS unavailable
- CNI connectivity issue
- UDP/TCP port 53 blocked
- NetworkPolicy restricting DNS
- incorrect resolver address
- broader network failure

---

## Operational Safety

The implementation uses several safeguards:

- CoreDNS is backed up before changes
- Service and DNS addresses are discovered dynamically
- no hard-coded kube-dns ClusterIP is required
- failure injection is reversible
- CoreDNS is restored after controlled failure
- finite retry loops are used
- finite log captures are used
- temporary port-forwards are terminated
- DNS health is checked before load generation
- post-recovery functionality is verified
- HTTP connectivity is verified in addition to DNS
- sensitive bootstrap information is excluded from version control

---

## Repository Structure

    kubernetes-coredns-operations/
    |
    +-- README.md
    |
    +-- manifests/
    |   |
    |   +-- sample-app-deployment.yaml
    |   +-- sample-app-service.yaml
    |   +-- dns-test-pod.yaml
    |   +-- coredns-custom-config.yaml
    |   +-- coredns-broken-config.yaml
    |   +-- advanced-dns-test-pod.yaml
    |   +-- dns-load-test.yaml
    |
    +-- evidence/
    |   |
    |   +-- coredns-environment.txt
    |   +-- dns-test-resolv-conf.txt
    |   +-- service-dns-baseline.txt
    |   +-- custom-domain-validation.txt
    |   +-- Corefile.custom-active
    |   +-- Corefile.broken
    |   +-- coredns-failure-logs.txt
    |   +-- coredns-failure-diagnosis.txt
    |   +-- advanced-resolv-conf.txt
    |   +-- Corefile.restored
    |   +-- coredns-recovery-logs.txt
    |   +-- coredns-recovery-validation.txt
    |   +-- task4-dns-baseline-recovery.txt
    |   +-- dns-load-test-results.txt
    |   +-- coredns-metrics-before-load.txt
    |   +-- coredns-metrics-after-load.txt
    |   +-- coredns-request-counters-before.txt
    |   +-- coredns-request-counters-after.txt
    |   +-- coredns-post-load-logs.txt
    |   +-- coredns-load-and-metrics-summary.txt
    |   +-- final-coredns-operations-summary.txt
    |   +-- coredns-troubleshooting-runbook.txt
    |
    +-- backups/
        |
        +-- Corefile.original
        +-- Corefile.before-failure

Only useful, non-sensitive operational artifacts are included.

---

## Skills Demonstrated

- Kubernetes administration
- kubeadm
- containerd
- Flannel networking
- CoreDNS
- Kubernetes DNS
- Kubernetes Services
- ClusterIP
- EndpointSlice inspection
- service discovery
- CoreDNS Corefile configuration
- custom DNS zones
- ConfigMap management
- DNS troubleshooting
- nslookup
- dig
- netcat
- resolver inspection
- CoreDNS logging
- controlled failure simulation
- failure recovery
- Prometheus metrics
- DNS load testing
- operational validation
- Linux networking
- root-cause analysis

---

## Operational Relevance

Kubernetes workloads commonly depend on DNS names rather than fixed IP addresses.

DNS failure can therefore appear as:

- service-to-service connectivity failure
- backend connection failure
- database connection failure
- upstream dependency failure
- apparent application outage
- apparent network outage

The troubleshooting workflow distinguishes among:

    workload failure
    Service failure
    endpoint failure
    DNS reachability failure
    CoreDNS configuration failure
    Kubernetes service-discovery failure

---

## Final Outcome

The complete operational flow is:

    Fresh Kubernetes Environment
              |
              v
    Healthy CoreDNS Baseline
              |
              v
    Kubernetes Service Discovery
              |
              v
    Custom DNS Configuration
              |
              v
    Controlled DNS Failure
              |
              v
    Failure Investigation
              |
              v
    Root Cause Identification
              |
              v
    CoreDNS Recovery
              |
              v
    DNS Baseline Revalidation
              |
              v
    Metrics Collection
              |
              v
    100-Query DNS Load Test
              |
              v
    Post-Load Validation
              |
              v
    Healthy CoreDNS Environment

The key result is the ability to configure, validate, troubleshoot, recover, monitor, and verify Kubernetes DNS behavior through a repeatable operational workflow.
