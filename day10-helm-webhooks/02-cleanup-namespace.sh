#!/usr/bin/env bash
# day10-helm-webhooks/02-cleanup-namespace.sh
# Cleans up everything Day 10 created, including objects a plain
# `kubectl delete namespace day10` would NOT handle:
#   - Helm releases (Helm tracks these separately from kubectl)
#   - The cluster-scoped ValidatingWebhookConfiguration
#   - The cluster-scoped CRD (deleted last, after clearing any Widget
#     finalizers first — deleting a CRD while a stuck finalizer exists
#     on one of its CRs will itself hang)
#   - The 'day10-stuck' namespace, force-unstuck if still Terminating
#
# Usage: chmod +x 02-cleanup-namespace.sh && ./02-cleanup-namespace.sh

set -euo pipefail
NS="day10"

echo "==> Uninstalling Helm releases (if present)..."
helm uninstall app-1 -n "${NS}" 2>/dev/null || true
helm uninstall app-2 -n "${NS}" 2>/dev/null || true

echo "==> Deleting cluster-scoped ValidatingWebhookConfiguration..."
kubectl delete validatingwebhookconfiguration app-3-webhook --ignore-not-found

echo "==> Clearing finalizers on any leftover Widget custom resources (prevents CRD/namespace hangs)..."
if kubectl get crd widgets.example.com &>/dev/null; then
  for ns in "${NS}" day10-stuck; do
    for w in $(kubectl get widgets -n "${ns}" -o name 2>/dev/null || true); do
      kubectl patch "${w}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    done
  done
fi

echo "==> Deleting 'day10-stuck' namespace..."
kubectl delete namespace day10-stuck --ignore-not-found --wait=true

echo "==> Deleting '${NS}' namespace..."
kubectl delete namespace "${NS}" --ignore-not-found --wait=true

echo "==> Deleting cluster-scoped CRD (widgets.example.com)..."
kubectl delete crd widgets.example.com --ignore-not-found

echo ""
echo "==> Done. Verify with:"
echo "    kubectl get namespace day10 day10-stuck"
echo "    kubectl get validatingwebhookconfiguration"
echo "    kubectl get crd widgets.example.com"
echo "==> Re-seed with: ./01-create-issues.sh"
