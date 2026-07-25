#!/usr/bin/env bash
# 00-setup-cluster.sh (AKS)
# Installs the Azure CLI if missing, then creates (or reuses) a shared AKS
# cluster that all day11-day15 folders use — same pattern as the kind days
# sharing one local cluster.
#
# THIS SCRIPT DOES NOT RUN `az login` FOR YOU. Authenticate manually first:
#   az login
#   az account set --subscription "<your-subscription-id-or-name>"
# Then run this script.
#
# COST WARNING: unlike the kind-based days, this creates real billable
# Azure resources (an AKS cluster + its underlying VMs, disks, etc.). It
# is NOT free and NOT instant (provisioning typically takes 5-15 minutes).
# Remember to run 03-delete-cluster.sh (and read its resource-group note)
# when you're done practicing to avoid ongoing charges.
#
# REVIEW THESE VARIABLES before running — defaults are placeholders:
RESOURCE_GROUP="aks-practice-rg"
LOCATION="eastus"
CLUSTER_NAME="aks-practice"
NODE_COUNT=2
NODE_VM_SIZE="Standard_D2s_v5"
K8S_VERSION=""   # leave empty to use AKS's current default GA version

set -euo pipefail

echo "==> Checking for the Azure CLI..."
if ! command -v az &>/dev/null; then
  echo "==> Installing Azure CLI..."
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
  echo "==> Azure CLI already installed: $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || az --version | head -1)"
fi

echo "==> Checking Azure CLI authentication..."
if ! az account show &>/dev/null; then
  echo ""
  echo "==> NOT LOGGED IN. Run the following, then re-run this script:"
  echo "    az login"
  echo "    az account set --subscription \"<your-subscription-id-or-name>\""
  exit 1
fi
echo "==> Logged in as:"
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table

echo "==> Ensuring kubectl is installed (az can install it if missing)..."
if ! command -v kubectl &>/dev/null; then
  az aks install-cli
fi

echo "==> Ensuring resource group '${RESOURCE_GROUP}' exists in ${LOCATION}..."
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output none

if az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" &>/dev/null; then
  echo "==> AKS cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  echo "==> Creating AKS cluster '${CLUSTER_NAME}' (this typically takes 5-15 minutes)..."
  VERSION_FLAG=()
  if [ -n "${K8S_VERSION}" ]; then
    VERSION_FLAG=(--kubernetes-version "${K8S_VERSION}")
  fi
  az aks create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --node-count "${NODE_COUNT}" \
    --node-vm-size "${NODE_VM_SIZE}" \
    --enable-managed-identity \
    --network-plugin azure \
    --generate-ssh-keys \
    "${VERSION_FLAG[@]}" \
    --output none
fi

echo "==> Fetching cluster credentials..."
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --overwrite-existing

echo "==> Cluster nodes:"
kubectl get nodes -o wide

echo ""
echo "==> Done. AKS cluster '${CLUSTER_NAME}' in resource group '${RESOURCE_GROUP}' is ready."
echo "==> Next: run ./01-create-issues.sh in this folder."
echo "==> REMINDER: this cluster costs money while it exists — see 03-delete-cluster.sh when done."
