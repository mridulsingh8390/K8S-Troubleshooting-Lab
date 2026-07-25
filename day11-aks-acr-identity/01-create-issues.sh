#!/usr/bin/env bash
# day11-aks-acr-identity/01-create-issues.sh
# Namespace: aks-day11 (plus an ACR and identity-related Azure resources
# in resource group aks-practice-rg)
#
# Theme: ACR image pull authentication and Azure Workload Identity —
# failure modes that don't exist on a local kind cluster at all.
#
# I have NOT been able to test this against a live Azure subscription.
# CLI flags/behavior may drift from what's documented here — treat this
# as a strong starting point to debug and adjust, not a guaranteed-exact
# script. Review the variables below before running.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
RESOURCE_GROUP="aks-practice-rg"
CLUSTER_NAME="aks-practice"
NS="aks-day11"
ACR_NAME="akspractice$(date +%s | tail -c 6)"   # ACR names must be globally unique

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating an Azure Container Registry (this is a real billable resource)..."
az acr create --resource-group "${RESOURCE_GROUP}" --name "${ACR_NAME}" --sku Basic --output none
echo "${ACR_NAME}" > /tmp/aks-day11-acr-name.txt
echo "==> ACR name saved to /tmp/aks-day11-acr-name.txt: ${ACR_NAME}"

echo "==> Pushing a placeholder image into the ACR (via 'az acr build', no local docker needed)..."
cat > /tmp/aks-day11-dockerfile <<'EOF'
FROM nginx:1.25
EOF
az acr build --registry "${ACR_NAME}" --image day11/app:v1 /tmp --file /tmp/aks-day11-dockerfile --output none

# [ANSWER KEY - app-1]: The AKS cluster's kubelet identity was never
# granted the AcrPull role on this ACR (i.e. the ACR was never attached
# to the cluster via `az aks update --attach-acr`, and no manual role
# assignment exists either). The image reference itself is correct —
# this is purely an authorization gap between AKS and ACR. You'll see
# ImagePullBackOff with an "unauthorized: authentication required"
# message in the pod's events.
# Fix: az aks update --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME} --attach-acr ${ACR_NAME}
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-1
  namespace: ${NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: app-1}}
  template:
    metadata: {labels: {app: app-1}}
    spec:
      containers:
        - name: app
          image: ${ACR_NAME}.azurecr.io/day11/app:v1
EOF

# [ANSWER KEY - app-2]: A ServiceAccount is annotated for Azure Workload
# Identity (client-id of a real or placeholder user-assigned managed
# identity), but the POD TEMPLATE is missing the required label
# "azure.workload.identity/use: \"true\"". Without that label, the
# workload identity mutating webhook never injects the projected token
# volume/env vars into the pod — any Azure SDK call inside the container
# using DefaultAzureCredential will fail with something like "no
# credential in this chain was able to authenticate", even though the
# ServiceAccount annotation and (if you set one up) the federated
# identity credential both look completely correct. This is the single
# most common Workload Identity gotcha — a missing pod-level label, not
# a missing Azure-side config.
# Fix: add "azure.workload.identity/use: \"true\"" to the pod template's
# labels (metadata.labels, not just the ServiceAccount's).
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workload-identity-sa
  namespace: ${NS}
  annotations:
    azure.workload.identity/client-id: "00000000-0000-0000-0000-000000000000"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-2
  namespace: ${NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: app-2}}
  template:
    metadata:
      labels: {app: app-2}
    spec:
      serviceAccountName: workload-identity-sa
      containers:
        - name: app
          image: mcr.microsoft.com/azure-cli:latest
          command: ["sh", "-c", "sleep infinity"]
EOF

# [ANSWER KEY - app-3]: An imagePullSecret is created using an ACR
# ADMIN-ACCOUNT username/password — but the password value baked into
# this Secret is a deliberately invalid/expired one. The Secret exists,
# is correctly formed (type kubernetes.io/dockerconfigjson), and is
# correctly referenced via imagePullSecrets — but ACR rejects the
# credential itself. This teaches checking whether a pull secret's
# CONTENTS are still valid, not just whether the Secret exists and is
# wired up correctly. (Using admin-account credentials in a Secret at
# all is also worth flagging as a security anti-pattern vs. attaching
# the ACR to the cluster's managed identity, as in app-1's fix.)
kubectl create secret docker-registry acr-pull-secret \
  --docker-server="${ACR_NAME}.azurecr.io" \
  --docker-username="00000000-0000-0000-0000-000000000000" \
  --docker-password="invalid-expired-token-placeholder" \
  -n "${NS}" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-3
  namespace: ${NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: app-3}}
  template:
    metadata: {labels: {app: app-3}}
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: app
          image: ${ACR_NAME}.azurecr.io/day11/app:v1
EOF

echo ""
echo "==> Done. Day 11 issues created in namespace '${NS}'."
echo "==> ACR created: ${ACR_NAME} (remember this for cleanup — saved in /tmp/aks-day11-acr-name.txt)"
echo "==> kubectl get pods -n ${NS}"
echo "==> kubectl describe pod <pod> -n ${NS}"
