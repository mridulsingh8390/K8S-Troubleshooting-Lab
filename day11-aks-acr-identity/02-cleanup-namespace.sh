#!/usr/bin/env bash
# day11-aks-acr-identity/02-cleanup-namespace.sh
# Deletes the 'aks-day11' namespace AND the ACR created alongside it —
# the ACR is an Azure resource, not a Kubernetes object, so a namespace
# delete alone won't remove it (and it costs money while it exists).

set -euo pipefail
RESOURCE_GROUP="aks-practice-rg"
NS="aks-day11"

echo "==> Deleting namespace '${NS}'..."
kubectl delete namespace "${NS}" --ignore-not-found --wait=true

if [ -f /tmp/aks-day11-acr-name.txt ]; then
  ACR_NAME="$(cat /tmp/aks-day11-acr-name.txt)"
  echo "==> Deleting ACR '${ACR_NAME}'..."
  az acr delete --resource-group "${RESOURCE_GROUP}" --name "${ACR_NAME}" --yes || true
  rm -f /tmp/aks-day11-acr-name.txt
else
  echo "==> No record of an ACR name found (/tmp/aks-day11-acr-name.txt missing)."
  echo "    Check manually: az acr list --resource-group ${RESOURCE_GROUP} --output table"
fi

echo ""
echo "==> Done. Re-seed with: ./01-create-issues.sh"
