#!/usr/bin/env bash
# day8-pv-statefulset/02-cleanup-namespace.sh
# Deletes the 'day8' namespace AND the 3 cluster-scoped PersistentVolumes
# created alongside it. PersistentVolumes are NOT namespaced, so a plain
# `kubectl delete namespace day8` would leave pv-1/pv-2/pv-3 behind.
#
# Usage: chmod +x 02-cleanup-namespace.sh && ./02-cleanup-namespace.sh

set -euo pipefail
NS="day8"

echo "==> Deleting namespace '${NS}' (Deployments, StatefulSets, PVCs)..."
kubectl delete namespace "${NS}" --ignore-not-found --wait=true

echo "==> Deleting cluster-scoped PersistentVolumes (pv-1, pv-2, pv-3)..."
kubectl delete pv pv-1 pv-2 pv-3 --ignore-not-found

echo ""
echo "==> Done. Verify with: kubectl get pv ; kubectl get ns"
echo "==> Re-seed with: ./01-create-issues.sh"
