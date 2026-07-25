#!/usr/bin/env bash
# 03-delete-cluster.sh
# Deletes the ENTIRE kind cluster (all days, all namespaces, everything).
# Use this only when you're fully done practicing and want a clean slate,
# or if the cluster itself is in a bad state and you'd rather rebuild it
# than debug it.
#
# For clearing just this day's issues and trying them again, use
# 02-cleanup-namespace.sh instead — it's much faster and doesn't require
# reinstalling anything.
#
# Usage: chmod +x 03-delete-cluster.sh && ./03-delete-cluster.sh

set -euo pipefail

CLUSTER_NAME="practice"

if ! command -v kind &>/dev/null; then
  echo "==> kind is not installed — nothing to delete."
  exit 0
fi

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> Deleting kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "==> Done. Run 00-setup-cluster.sh again to recreate it."
else
  echo "==> No kind cluster named '${CLUSTER_NAME}' found — nothing to delete."
fi
