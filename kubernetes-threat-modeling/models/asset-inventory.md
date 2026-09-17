# Critical Asset Inventory

## Data Assets

### Customer / Application Data
Location:
PostgreSQL database

Security requirements:
- confidentiality
- integrity
- availability

Primary threats:
- unauthorized database access
- lateral movement
- credential theft
- destructive operations

### Database Credentials
Location:
Kubernetes Secret

Security requirements:
- confidentiality
- controlled access
- rotation

Primary threats:
- Secret read permissions
- ServiceAccount compromise
- accidental exposure

## Identity Assets

### Kubernetes ServiceAccounts
Security requirements:
- least privilege
- workload isolation
- short-lived credentials

Primary threats:
- token theft
- excessive RBAC
- identity reuse

## Control Plane Assets

### Kubernetes API Server
Security requirements:
- authentication
- authorization
- availability
- auditability

Primary threats:
- stolen workload credentials
- privilege escalation
- API abuse

## Compute Assets

### Kubernetes Node
Security requirements:
- workload isolation
- runtime integrity

Primary threats:
- privileged container access
- hostPath abuse
- container escape

### Application Pods
Security requirements:
- non-root execution
- least privilege
- restricted filesystem access

Primary threats:
- vulnerable image
- runtime compromise
- lateral movement

## Network Assets

### Cluster Network
Security requirements:
- segmentation
- restricted east-west access

Primary threats:
- unrestricted service discovery
- lateral movement
- direct database access

## Availability Assets

### Frontend
Business role:
External application entry point

### Backend
Business role:
Application logic tier

### Database
Business role:
Persistent data tier
