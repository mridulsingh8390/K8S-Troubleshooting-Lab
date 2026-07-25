#!/usr/bin/env bash
# day18-aks-keyvault-csi/02-cleanup-namespace.sh
# Deletes the 'aks-day18' namespace AND the Key Vault created alongside
# it. Key Vaults soft-delete by default in Azure (they linger in a
# recoverable state for a retention period even after deletion) — this
# script issues the delete; if you also want to purge it immediately
# (skip the soft-delete retention), see the commented purge command.

set -euo pipefail
RESOURCE_GROUP="aks-practice-rg"
NS="aks-day18"

echo "==> Deleting namespace '${NS}'..."
kubectl delete namespace "${NS}" --ignore-not-found --wait=true

if [ -f /tmp/aks-day18-kv-name.txt ]; then
  KV_NAME="$(cat /tmp/aks-day18-kv-name.txt)"
  echo "==> Deleting Key Vault '${KV_NAME}'..."
  az keyvault delete --resource-group "${RESOURCE_GROUP}" --name "${KV_NAME}" || true
  echo "==> Note: Key Vaults soft-delete by default. To fully purge (optional,"
  echo "    frees up the name immediately instead of after the retention period):"
  echo "    az keyvault purge --name ${KV_NAME}"
  rm -f /tmp/aks-day18-kv-name.txt
else
  echo "==> No record of a Key Vault name found (/tmp/aks-day18-kv-name.txt missing)."
  echo "    Check manually: az keyvault list --resource-group ${RESOURCE_GROUP} --output table"
fi

echo ""
echo "==> Done. Re-seed with: ./01-create-issues.sh"
