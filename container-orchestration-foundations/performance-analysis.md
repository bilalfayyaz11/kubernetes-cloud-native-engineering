# Performance and Operational Analysis

## Manual Scaling

Five application instances were deployed manually using a shell script.

Each instance required:
- a unique container name
- a unique host port
- explicit creation
- explicit verification

This demonstrates that manual container scaling requires additional coordination as replica count increases.

## Failure Recovery

Two application containers were intentionally stopped.

The environment required:
1. identifying failed instances
2. confirming unavailable endpoints
3. restarting each failed container
4. retesting the application

The desired application state was not automatically restored.

## Load Balancing

A separate nginx service was installed and configured to distribute requests across five container instances.

The backend endpoints were manually declared in nginx configuration.

Any change to replica count or backend ports would require corresponding load-balancer configuration changes.

## Resource Management

Resource usage was inspected using Docker statistics.

One container was explicitly configured with:
- 128 MB memory limit
- 0.5 CPU limit

This demonstrates that resource governance must be manually applied when workloads are managed directly with Docker.

## Operational Conclusion

The experiment demonstrates that direct container management works for small environments but creates increasing operational overhead as applications scale.

The primary limitations observed were:
- manual endpoint allocation
- manual scaling
- manual failure recovery
- separate load-balancer management
- decentralized configuration
- manual resource controls
