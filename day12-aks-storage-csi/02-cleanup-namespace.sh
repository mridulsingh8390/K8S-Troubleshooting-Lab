#!/usr/bin/env bash
# day12-aks-storage-csi/02-cleanup-namespace.sh
# Deletes the 'aks-day12' namespace. Azure Disk/File CSI provisions real
# Azure Disks and Storage Accounts behind the scenes for dynamically
# provisioned PVCs — deleting the PVCs (via the namespace delete) should
# trigger the CSI driver to clean those up too under the default Delete
# reclaim policy, but it's worth verifying nothing was left behind.

set -euo pipefail
NS="aks-day12"

echo "==> Deleting namespace '${NS}' (this should also trigger deletion of the"
echo "    dynamically-provisioned Azure Disks/Storage Accounts behind pvc-1/2/3,"
echo "    assuming the default 'Delete' reclaim policy)..."
kubectl delete namespace "${NS}" --ignore-not-found --wait=true

echo ""
echo "==> Verify no orphaned Azure Disks were left behind:"
echo "    az disk list --resource-group MC_aks-practice-rg_aks-practice_<region> --output table"
echo "==> Verify no orphaned Storage Accounts (from azurefile-csi) were left behind:"
echo "    az storage account list --resource-group MC_aks-practice-rg_aks-practice_<region> --output table"
echo "==> Re-seed with: ./01-create-issues.sh"
