#!/usr/bin/env bash
# 03-delete-cluster.sh (AKS)
# Deletes the AKS cluster itself. Use when fully done with day11-day15.
#
# IMPORTANT: this deletes the AKS cluster, but some resources created by
# individual days' 01-create-issues.sh scripts (an Azure Container
# Registry in day11, an Application Gateway in day13, extra node pools in
# day15, etc.) live in the SAME resource group and are NOT automatically
# removed by `az aks delete` alone. The most reliable way to guarantee
# you stop being billed for everything created across day11-day15 is to
# delete the entire resource group:
#
#   az group delete --name aks-practice-rg --yes --no-wait
#
# Only do that once you're sure nothing else important lives in that
# resource group. This script deletes just the AKS cluster by default and
# reminds you about the resource group option — it does NOT delete the
# resource group automatically, since that's a wider blast radius than
# "delete the cluster."

set -euo pipefail

RESOURCE_GROUP="aks-practice-rg"
CLUSTER_NAME="aks-practice"

if ! command -v az &>/dev/null; then
  echo "==> Azure CLI is not installed — nothing to delete."
  exit 0
fi

if ! az account show &>/dev/null; then
  echo "==> Not logged in to Azure CLI. Run 'az login' first if you want this script to delete anything."
  exit 1
fi

if az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" &>/dev/null; then
  echo "==> Deleting AKS cluster '${CLUSTER_NAME}' in resource group '${RESOURCE_GROUP}'..."
  az aks delete --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" --yes --no-wait
  echo "==> Deletion started (--no-wait). Check progress with:"
  echo "    az aks show --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME} --query provisioningState"
else
  echo "==> No AKS cluster named '${CLUSTER_NAME}' found in '${RESOURCE_GROUP}' — nothing to delete."
fi

echo ""
echo "==> To also remove EVERYTHING ELSE created across day11-day15 (ACR, Application"
echo "    Gateway, extra node pools, managed identities, etc.) and guarantee no ongoing"
echo "    charges, delete the whole resource group instead:"
echo "        az group delete --name ${RESOURCE_GROUP} --yes --no-wait"
