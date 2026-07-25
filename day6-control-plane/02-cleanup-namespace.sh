#!/usr/bin/env bash
# day6-control-plane/02-cleanup-namespace.sh
# Unlike other days, Day 6's issues aren't purely namespace-scoped — some
# live on the nodes themselves. This script best-effort reverts everything:
# static pod manifests, kubelet state, and the day6 namespace. If any of
# app-1/app-2/app-3 are still broken when you run this (i.e. you're
# resetting instead of having fixed them yourself), it repairs them too.
#
# If this ever gets the cluster into a confusing state, 03-delete-cluster.sh
# followed by 00-setup-cluster.sh is always a clean fallback.
#
# Usage: chmod +x 02-cleanup-namespace.sh && ./02-cleanup-namespace.sh

set -euo pipefail
NS="day6"
CP_NODE="practice-control-plane"
WORKER2_NODE="practice-worker2"

echo "==> Reverting kube-scheduler static pod manifest on ${CP_NODE} (if still broken)..."
docker exec "${CP_NODE}" sed -i '/--this-flag-does-not-exist=true/d' \
  /etc/kubernetes/manifests/kube-scheduler.yaml 2>/dev/null || true

echo "==> Reverting kube-controller-manager static pod manifest on ${CP_NODE} (if still broken)..."
docker exec "${CP_NODE}" sed -i '/--this-flag-does-not-exist=true/d' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml 2>/dev/null || true

echo "==> Ensuring kubelet is running on ${WORKER2_NODE}..."
docker exec "${WORKER2_NODE}" systemctl start kubelet 2>/dev/null || true

echo "==> Deleting namespace '${NS}' (removes app-4's disk-filling pod and app-5's leftovers)..."
kubectl delete namespace "${NS}" --ignore-not-found --wait=true

echo "==> Removing the etcd snapshot file left on ${CP_NODE} (frees disk)..."
docker exec "${CP_NODE}" rm -f /var/lib/etcd/day6-snapshot.db 2>/dev/null || true

echo ""
echo "==> Done. Verify with: kubectl get pods -A ; kubectl get nodes"
echo "==> Re-seed with: ./01-create-issues.sh"
