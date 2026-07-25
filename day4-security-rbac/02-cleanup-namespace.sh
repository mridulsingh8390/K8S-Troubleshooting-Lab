#!/usr/bin/env bash
# day4-security-rbac/02-cleanup.sh
# Deletes the day4 namespace AND the cluster-scoped ClusterRoleBinding
# created alongside it (ClusterRoleBindings are not namespaced, so deleting
# the namespace alone won't remove it).
set -euo pipefail
kubectl delete clusterrolebinding overprivileged-binding-day4 --ignore-not-found
kubectl delete namespace day4 --ignore-not-found --wait=true
echo "==> day4 namespace and ClusterRoleBinding removed. Re-seed with ./01-create-issues.sh"
