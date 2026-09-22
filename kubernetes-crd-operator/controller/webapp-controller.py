#!/usr/bin/env python3

import os
import time
import traceback
from datetime import datetime, timezone

from kubernetes import client, config
from kubernetes.client.rest import ApiException


GROUP = "platform.example"
VERSION = "v1"
PLURAL = "webapps"

RECONCILE_INTERVAL = int(os.getenv("RECONCILE_INTERVAL", "10"))


def now_rfc3339():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_configuration():
    try:
        config.load_incluster_config()
        print("Loaded in-cluster Kubernetes configuration", flush=True)
    except config.ConfigException:
        config.load_kube_config()
        print("Loaded local kubeconfig", flush=True)


custom_api = None
apps_api = None
core_api = None



def owner_reference_dict(webapp):
    metadata = webapp["metadata"]

    return {
        "apiVersion": f"{GROUP}/{VERSION}",
        "kind": "WebApp",
        "name": metadata["name"],
        "uid": metadata["uid"],
        "controller": True,
        "blockOwnerDeletion": True,
    }


def reconcile_deployment(webapp):
    metadata = webapp["metadata"]
    spec = webapp["spec"]

    name = metadata["name"]
    namespace = metadata.get("namespace", "default")
    deployment_name = f"{name}-deployment"

    labels = {
        "app.kubernetes.io/name": name,
        "app.kubernetes.io/managed-by": "webapp-controller",
        "platform.example/webapp": name,
    }

    env = [
        {
            "name": item["name"],
            "value": item["value"],
        }
        for item in spec.get("env", [])
    ]

    desired_patch = {
        "metadata": {
            "labels": labels,
            "ownerReferences": [
                owner_reference_dict(webapp)
            ],
        },
        "spec": {
            "replicas": spec["replicas"],
            "selector": {
                "matchLabels": {
                    "platform.example/webapp": name
                }
            },
            "template": {
                "metadata": {
                    "labels": labels
                },
                "spec": {
                    "containers": [
                        {
                            "name": "webapp",
                            "image": spec["image"],
                            "ports": [
                                {
                                    "containerPort": spec["port"]
                                }
                            ],
                            "env": env,
                            "resources": {
                                "requests": {
                                    "cpu": "10m",
                                    "memory": "16Mi",
                                },
                                "limits": {
                                    "cpu": "100m",
                                    "memory": "128Mi",
                                },
                            },
                        }
                    ]
                },
            },
        },
    }

    try:
        apps_api.read_namespaced_deployment(
            name=deployment_name,
            namespace=namespace,
        )

        apps_api.patch_namespaced_deployment(
            name=deployment_name,
            namespace=namespace,
            body=desired_patch,
        )

        print(
            f"Reconciled Deployment {namespace}/{deployment_name}",
            flush=True,
        )

    except ApiException as exc:
        if exc.status != 404:
            raise

        body = {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {
                "name": deployment_name,
                "namespace": namespace,
                "labels": labels,
                "ownerReferences": [
                    owner_reference_dict(webapp)
                ],
            },
            "spec": desired_patch["spec"],
        }

        apps_api.create_namespaced_deployment(
            namespace=namespace,
            body=body,
        )

        print(
            f"Created Deployment {namespace}/{deployment_name}",
            flush=True,
        )


def reconcile_service(webapp):
    metadata = webapp["metadata"]
    spec = webapp["spec"]

    name = metadata["name"]
    namespace = metadata.get("namespace", "default")
    service_name = f"{name}-service"

    labels = {
        "app.kubernetes.io/name": name,
        "app.kubernetes.io/managed-by": "webapp-controller",
        "platform.example/webapp": name,
    }

    owner_refs = [
        owner_reference_dict(webapp)
    ]

    desired_ports = [
        {
            "name": "http",
            "protocol": "TCP",
            "port": spec["port"],
            "targetPort": spec["port"],
        }
    ]

    selector = {
        "platform.example/webapp": name
    }

    try:
        current = core_api.read_namespaced_service(
            name=service_name,
            namespace=namespace,
        )

        # Serialize the live Service using Kubernetes API field names.
        current_dict = client.ApiClient().sanitize_for_serialization(
            current
        )

        current_spec = current_dict.get("spec", {})

        body = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {
                "name": service_name,
                "namespace": namespace,
                "resourceVersion": current_dict["metadata"]["resourceVersion"],
                "labels": labels,
                "ownerReferences": owner_refs,
            },
            "spec": {
                "selector": selector,
                "ports": desired_ports,
                "type": "ClusterIP",
            },
        }

        # Preserve API-assigned networking values.
        for field in (
            "clusterIP",
            "clusterIPs",
            "ipFamilies",
            "ipFamilyPolicy",
            "sessionAffinity",
            "internalTrafficPolicy",
        ):
            value = current_spec.get(field)

            if value is not None:
                body["spec"][field] = value

        core_api.replace_namespaced_service(
            name=service_name,
            namespace=namespace,
            body=body,
        )

        print(
            f"Reconciled Service {namespace}/{service_name}",
            flush=True,
        )

    except ApiException as exc:
        if exc.status != 404:
            raise

        body = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {
                "name": service_name,
                "namespace": namespace,
                "labels": labels,
                "ownerReferences": owner_refs,
            },
            "spec": {
                "selector": selector,
                "ports": desired_ports,
                "type": "ClusterIP",
            },
        }

        core_api.create_namespaced_service(
            namespace=namespace,
            body=body,
        )

        print(
            f"Created Service {namespace}/{service_name}",
            flush=True,
        )


def update_status(webapp):
    metadata = webapp["metadata"]
    name = metadata["name"]
    namespace = metadata.get("namespace", "default")
    generation = metadata.get("generation", 0)

    deployment_name = f"{name}-deployment"

    available = 0

    try:
        deployment = apps_api.read_namespaced_deployment_status(
            name=deployment_name,
            namespace=namespace,
        )

        available = (
            deployment.status.available_replicas
            or 0
        )

    except ApiException as exc:
        if exc.status != 404:
            raise

    desired_replicas = webapp["spec"]["replicas"]

    ready = available >= desired_replicas

    status = {
        "status": {
            "observedGeneration": generation,
            "availableReplicas": available,
            "conditions": [
                {
                    "type": "Ready",
                    "status": "True" if ready else "False",
                    "observedGeneration": generation,
                    "lastTransitionTime": now_rfc3339(),
                    "reason": (
                        "DeploymentReady"
                        if ready
                        else "DeploymentProgressing"
                    ),
                    "message": (
                        f"{available}/{desired_replicas} replicas available"
                    ),
                }
            ],
        }
    }

    custom_api.patch_namespaced_custom_object_status(
        group=GROUP,
        version=VERSION,
        namespace=namespace,
        plural=PLURAL,
        name=name,
        body=status,
    )

    print(
        f"Updated status for {namespace}/{name}: "
        f"{available}/{desired_replicas} available",
        flush=True,
    )


def reconcile(webapp):
    metadata = webapp["metadata"]

    name = metadata["name"]
    namespace = metadata.get("namespace", "default")

    print(
        f"Reconciling WebApp {namespace}/{name}",
        flush=True,
    )

    # Reconcile desired child resources first.
    reconcile_deployment(webapp)
    reconcile_service(webapp)

    # Always refresh observed state after child reconciliation.
    update_status(webapp)

    print(
        f"Completed reconciliation for {namespace}/{name}",
        flush=True,
    )


def reconcile_all():
    namespace = os.getenv("WATCH_NAMESPACE", "default")

    result = custom_api.list_namespaced_custom_object(
        group=GROUP,
        version=VERSION,
        namespace=namespace,
        plural=PLURAL,
    )

    items = result.get("items", [])

    print(
        f"Found {len(items)} WebApp resource(s)",
        flush=True,
    )

    for webapp in items:
        try:
            reconcile(webapp)
        except Exception:
            print(
                f"Reconcile failed for "
                f"{webapp.get('metadata', {}).get('name', 'unknown')}",
                flush=True,
            )
            traceback.print_exc()


def main():
    global custom_api
    global apps_api
    global core_api

    load_configuration()

    custom_api = client.CustomObjectsApi()
    apps_api = client.AppsV1Api()
    core_api = client.CoreV1Api()

    print(
        f"WebApp controller started; "
        f"reconcile interval={RECONCILE_INTERVAL}s",
        flush=True,
    )

    while True:
        try:
            reconcile_all()
        except Exception:
            traceback.print_exc()

        time.sleep(RECONCILE_INTERVAL)


if __name__ == "__main__":
    main()
