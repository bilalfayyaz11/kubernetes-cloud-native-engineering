# Container Management Challenges Report

## 1. Port Conflicts
- Issue: Multiple containers cannot bind to the same host port.
- Manual Solution: Track and assign unique host ports for every container.
- Operational Impact: Port coordination becomes difficult as the number of services increases.

## 2. Resource Management
- Issue: Containers can consume CPU and memory without defined limits.
- Manual Solution: Configure resource constraints individually for each container.
- Operational Impact: Poorly controlled workloads can cause resource contention and instability.

## 3. Scaling Challenges
- Issue: Scaling requires manually starting and configuring additional containers.
- Manual Solution: Use scripts to create replicas and manually assign ports.
- Operational Impact: Scaling becomes repetitive, error-prone, and difficult to maintain.

## 4. Failure Recovery
- Issue: Failed containers do not automatically restore the desired application state.
- Manual Solution: Detect failed containers and restart them manually.
- Operational Impact: Recovery depends on monitoring and operator intervention.

## 5. Load Balancing
- Issue: Standalone containers do not automatically distribute incoming traffic.
- Manual Solution: Configure and maintain a separate reverse proxy or load balancer.
- Operational Impact: Backend changes require load-balancer configuration updates.

## 6. Service Discovery
- Issue: Applications depend on manually tracked addresses and ports.
- Manual Solution: Maintain endpoint information manually.
- Operational Impact: Configuration becomes fragile when containers or endpoints change.

## 7. Configuration Management
- Issue: Configuration is distributed across individual containers and scripts.
- Manual Solution: Update each workload or deployment process separately.
- Operational Impact: Configuration drift and inconsistent environments become more likely.
