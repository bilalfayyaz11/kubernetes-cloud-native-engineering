#!/usr/bin/env bash

# Reference-only disaster recovery workflow.
#
# Do not execute blindly on a production cluster.
# Stop all API servers before restoring etcd.
#
# 1. Validate snapshot:
#    sudo etcdutl snapshot status /secure/path/snapshot.db --write-out=table
#
# 2. Stop kube-apiserver static Pod by moving its manifest out of:
#    /etc/kubernetes/manifests/
#
# 3. Stop etcd static Pod the same way.
#
# 4. Preserve the existing /var/lib/etcd directory.
#
# 5. Restore using etcdutl with the kubeadm etcd member identity:
#
#    sudo etcdutl snapshot restore /secure/path/snapshot.db \
#      --data-dir=/var/lib/etcd \
#      --name=<etcd-member-name> \
#      --initial-cluster='<member>=https://<peer-ip>:2380' \
#      --initial-advertise-peer-urls=https://<peer-ip>:2380
#
# 6. Restore the etcd static Pod manifest.
#
# 7. Validate etcd endpoint health.
#
# 8. Restore kube-apiserver manifest.
#
# 9. Verify /readyz and Kubernetes objects.
#
# 10. Restart controller-manager, scheduler, and kubelet as appropriate.
#
# Never commit an etcd snapshot to source control.
