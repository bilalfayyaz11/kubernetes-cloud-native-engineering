# Data Flow Model

## DF-01
External Client -> Frontend Service

Data:
HTTP request/response

Trust transition:
Untrusted external source enters cluster workload boundary

## DF-02
Frontend -> Backend

Data:
Application API traffic

Trust transition:
Web tier crosses into application tier

## DF-03
Backend -> Database

Data:
Database queries and responses

Trust transition:
Application tier enters sensitive data tier

## DF-04
Pod -> Kubernetes API

Data:
ServiceAccount bearer token + API requests

Trust transition:
Workload identity enters control-plane trust boundary

## DF-05
Container -> Host

Data:
Normally none

Trust transition:
Container isolation boundary

Security concern:
Privileged execution, host mounts, or dangerous capabilities can collapse this boundary.
