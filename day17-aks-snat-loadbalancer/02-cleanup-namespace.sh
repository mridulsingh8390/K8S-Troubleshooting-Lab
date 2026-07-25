#!/usr/bin/env bash
# day17-aks-snat-loadbalancer/02-cleanup-namespace.sh
# Deletes the namespace. Note: app-1's Service never successfully
# provisioned a Load Balancer frontend IP (that was the bug), so there's
# nothing extra to clean up there. app-3's internal LoadBalancer Service
# DID provision a real (private) Azure Load Balancer frontend IP — the
# namespace delete removes the Service, which should trigger Azure to
# deprovision that too, but it's worth a quick check.

set -euo pipefail
NS="aks-day17"

echo "==> Deleting namespace '${NS}'..."
kubectl delete namespace "${NS}" --ignore-not-found --wait=true

echo ""
echo "==> Verify no orphaned Load Balancer frontend configs were left behind:"
echo "    az network lb frontend-ip list --lb-name kubernetes --resource-group MC_aks-practice-rg_aks-practice_<region> --output table"
echo "==> Re-seed with: ./01-create-issues.sh"
