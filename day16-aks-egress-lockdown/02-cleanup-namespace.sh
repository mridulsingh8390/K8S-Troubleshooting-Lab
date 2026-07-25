#!/usr/bin/env bash
# day16-aks-egress-lockdown/02-cleanup-namespace.sh
set -euo pipefail
kubectl delete namespace aks-day16 --ignore-not-found --wait=true
echo "==> aks-day16 namespace removed."
echo "==> If you built a real Azure Firewall setup for app-2's guided exercise, that is"
echo "    separate billable infrastructure this script does NOT remove — check:"
echo "    az network firewall list --resource-group aks-practice-rg --output table"
echo "==> Re-seed with: ./01-create-issues.sh"
