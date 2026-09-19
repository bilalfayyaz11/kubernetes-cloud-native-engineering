#!/usr/bin/env python3

import time
from kubernetes import client, config

GROUP = "example.com"
VERSION = "v1"
PLURAL = "webapps"


def load_config():
    config.load_incluster_config()


def build_desired_deployment(name, namespace, spec):
    resources = spec.get("resources", {})

    requests = {}

    if resources.get("cpu"):
        requests["cpu"] = resources["cpu"]

    if resources.get("memory"):
        requests["memory"] = resources["memory"]

    return client.V1Deployment(
        api_version="apps/v1",
        kind="Deployment",
        metadata=client.V1ObjectMeta(
            name=f"{name}-deployment",
            namespace=namespace,
            labels={
                "app": name,
                "managed-by": "webapp-operator"
            }
        ),
        spec=client.V1DeploymentSpec(
            replicas=spec.get("replicas", 1),
            selector=client.V1LabelSelector(
                match_labels={
                    "app": name
                }
            ),
            template=client.V1PodTemplateSpec(
                metadata=client.V1ObjectMeta(
                    labels={
                        "app": name,
                        "managed-by": "webapp-operator"
                    }
                ),
                spec=client.V1PodSpec(
                    containers=[
                        client.V1Container(
                            name=name,
                            image=spec.get(
                                "image",
                                "nginx:latest"
                            ),
                            ports=[
                                client.V1ContainerPort(
                                    container_port=spec.get(
                                        "port",
                                        80
                                    )
                                )
                            ],
                            resources=client.V1ResourceRequirements(
                                requests=requests
                            )
                        )
                    ]
                )
            )
        )
    )


def reconcile_deployment(apps_api, name, namespace, spec):
    deployment_name = f"{name}-deployment"

    desired = build_desired_deployment(
        name,
        namespace,
        spec
    )

    try:
        current = apps_api.read_namespaced_deployment(
            name=deployment_name,
            namespace=namespace
        )

        current_container = \
            current.spec.template.spec.containers[0]

        desired_container = \
            desired.spec.template.spec.containers[0]

        changed = False

        if current.spec.replicas != desired.spec.replicas:
            current.spec.replicas = desired.spec.replicas
            changed = True

        if current_container.image != desired_container.image:
            current_container.image = desired_container.image
            changed = True

        current_port = None

        if current_container.ports:
            current_port = \
                current_container.ports[0].container_port

        desired_port = \
            desired_container.ports[0].container_port

        if current_port != desired_port:
            current_container.ports = [
                client.V1ContainerPort(
                    container_port=desired_port
                )
            ]
            changed = True

        current_requests = (
            current_container.resources.requests
            if current_container.resources
            else {}
        ) or {}

        desired_requests = (
            desired_container.resources.requests
            if desired_container.resources
            else {}
        ) or {}

        if current_requests != desired_requests:
            current_container.resources = \
                client.V1ResourceRequirements(
                    requests=desired_requests
                )
            changed = True

        desired_labels = {
            "app": name,
            "managed-by": "webapp-operator"
        }

        if current.spec.template.metadata.labels != desired_labels:
            current.spec.template.metadata.labels = desired_labels
            changed = True

        if changed:
            apps_api.patch_namespaced_deployment(
                name=deployment_name,
                namespace=namespace,
                body=current
            )

            print(
                f"Updated Deployment "
                f"{namespace}/{deployment_name}",
                flush=True
            )

        else:
            print(
                f"Deployment "
                f"{namespace}/{deployment_name} "
                f"already matches desired state",
                flush=True
            )

    except client.exceptions.ApiException as exc:
        if exc.status == 404:
            apps_api.create_namespaced_deployment(
                namespace=namespace,
                body=desired
            )

            print(
                f"Created Deployment "
                f"{namespace}/{deployment_name}",
                flush=True
            )

        else:
            raise


def update_status(custom_api, apps_api, name, namespace):
    deployment_name = f"{name}-deployment"

    available = 0
    ready = 0

    try:
        deployment = apps_api.read_namespaced_deployment(
            name=deployment_name,
            namespace=namespace
        )

        available = \
            deployment.status.available_replicas or 0

        ready = \
            deployment.status.ready_replicas or 0

    except client.exceptions.ApiException as exc:
        if exc.status != 404:
            raise

    patch = {
        "status": {
            "availableReplicas": available,
            "conditions": [
                {
                    "type": "Ready",
                    "status": (
                        "True"
                        if ready > 0
                        else "False"
                    ),
                    "lastTransitionTime": time.strftime(
                        "%Y-%m-%dT%H:%M:%SZ",
                        time.gmtime()
                    ),
                    "reason": (
                        "DeploymentReady"
                        if ready > 0
                        else "DeploymentNotReady"
                    ),
                    "message": (
                        f"Deployment has "
                        f"{ready} ready replicas"
                    )
                }
            ]
        }
    }

    custom_api.patch_namespaced_custom_object_status(
        group=GROUP,
        version=VERSION,
        namespace=namespace,
        plural=PLURAL,
        name=name,
        body=patch
    )


def reconcile_all():
    apps_api = client.AppsV1Api()
    custom_api = client.CustomObjectsApi()

    resources = custom_api.list_cluster_custom_object(
        group=GROUP,
        version=VERSION,
        plural=PLURAL
    )

    for resource in resources.get("items", []):
        metadata = resource.get("metadata", {})
        spec = resource.get("spec", {})

        name = metadata["name"]
        namespace = metadata.get(
            "namespace",
            "default"
        )

        print(
            f"Reconciling WebApp "
            f"{namespace}/{name}",
            flush=True
        )

        reconcile_deployment(
            apps_api,
            name,
            namespace,
            spec
        )

        update_status(
            custom_api,
            apps_api,
            name,
            namespace
        )


def main():
    load_config()

    print(
        "WebApp Operator started",
        flush=True
    )

    while True:
        try:
            reconcile_all()

        except Exception as exc:
            print(
                f"Reconciliation error: {exc}",
                flush=True
            )

        time.sleep(10)


if __name__ == "__main__":
    main()
