#!/usr/bin/env bash
# day15-aks-autoscaler-nodepools/02-cleanup-namespace.sh
# Deletes the 'aks-day15' namespace AND the dedicated node pool created
# alongside it — the node pool is a real, billable set of Azure VMs, not
# a Kubernetes object, so a namespace delete alone won't remove it.

set -euo pipefail
RESOURCE_GROUP="aks-practice-rg"
CLUSTER_NAME="aks-practice"
NS="aks-day15"
NODEPOOL_NAME="day15pool"

echo "==> Deleting namespace '${NS}'..."
kubectl delete namespace "${NS}" --ignore-not-found --wait=true

if az aks nodepool show --resource-group "${RESOURCE_GROUP}" --cluster-name "${CLUSTER_NAME}" --name "${NODEPOOL_NAME}" &>/dev/null; then
  echo "==> Deleting node pool '${NODEPOOL_NAME}' (this takes a few minutes)..."
  az aks nodepool delete \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${NODEPOOL_NAME}" \
    --no-wait
  echo "==> Deletion started (--no-wait). Check progress with:"
  echo "    az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name ${NODEPOOL_NAME} --query provisioningState"
else
  echo "==> No node pool named '${NODEPOOL_NAME}' found — nothing to delete."
fi

echo ""
echo "==> NOTE: this script does NOT revert the autoscaler min/max settings changed"
echo "    on the default 'nodepool1' — adjust those back if needed:"
echo "    az aks nodepool update --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name nodepool1 --update-cluster-autoscaler --min-count 1 --max-count 3"
echo "==> Re-seed with: ./01-create-issues.sh"
