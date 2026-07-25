#!/usr/bin/env bash
# day14-aks-rbac-aad/02-cleanup-namespace.sh
set -euo pipefail
kubectl delete namespace aks-day14 --ignore-not-found --wait=true
echo "==> aks-day14 namespace removed."
echo "==> If you ran 'az aks get-credentials --admin' for app-3's exercise, consider"
echo "    removing that context from your local kubeconfig if you don't want it lingering:"
echo "    kubectl config get-contexts | grep admin"
echo "    kubectl config delete-context <admin-context-name>"
echo "==> If you enabled Azure RBAC mode for app-2's exercise, that's a cluster-level"
echo "    setting, not something this script reverts — see 'az aks update --disable-azure-rbac'"
echo "    if you want to turn it back off."
echo "==> Re-seed with: ./01-create-issues.sh"
