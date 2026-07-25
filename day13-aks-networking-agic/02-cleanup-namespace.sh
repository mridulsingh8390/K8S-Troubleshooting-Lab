#!/usr/bin/env bash
# day13-aks-networking-agic/02-cleanup-namespace.sh
set -euo pipefail
kubectl delete namespace aks-day13 --ignore-not-found --wait=true
echo "==> aks-day13 namespace removed."
echo "==> If you provisioned an Application Gateway/AGIC add-on for app-2's manual"
echo "    exercise, that is a separate billable resource this script does NOT remove —"
echo "    check: az network application-gateway list --resource-group aks-practice-rg --output table"
echo "==> Re-seed with: ./01-create-issues.sh"
