#!/usr/bin/env bash
# day18-aks-keyvault-csi/01-create-issues.sh
# Namespace: aks-day18 (plus a real Azure Key Vault in aks-practice-rg)
#
# Theme: the Secrets Store CSI Driver + Azure Key Vault provider — the
# standard, real-world AKS pattern for pulling secrets at runtime instead
# of storing them as Kubernetes Secrets. All 3 issues here ARE fully
# scriptable (unlike some of day13/14/16/17's guided exercises).
#
# I have NOT been able to test this against a live Azure subscription —
# review before running, especially the addon-enable step (the exact
# flag/addon name has changed across AKS CLI versions).
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
RESOURCE_GROUP="aks-practice-rg"
CLUSTER_NAME="aks-practice"
LOCATION="eastus"
NS="aks-day18"
KV_NAME="akspractice-kv-$(date +%s | tail -c 6)"   # Key Vault names must be globally unique

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Enabling the Secrets Store CSI Driver add-on (azure-keyvault-secrets-provider)..."
az aks enable-addons \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --addons azure-keyvault-secrets-provider \
  --output none || echo "==> NOTE: addon may already be enabled, or the addon name has changed in newer az CLI versions — check 'az aks addon list --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME}'."

echo "==> Creating a real Key Vault and a secret inside it..."
az keyvault create --resource-group "${RESOURCE_GROUP}" --name "${KV_NAME}" --location "${LOCATION}" --output none
az keyvault secret set --vault-name "${KV_NAME}" --name "db-password" --value "correct-horse-battery-staple" --output none
echo "${KV_NAME}" > /tmp/aks-day18-kv-name.txt
echo "==> Key Vault name saved to /tmp/aks-day18-kv-name.txt: ${KV_NAME}"

echo "==> Fetching the AKS Key Vault add-on's identity (used for app-2's grant)..."
KUBELET_IDENTITY_CLIENT_ID=$(az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" \
  --query "identityProfile.kubeletidentity.clientId" -o tsv 2>/dev/null || echo "")
KUBELET_IDENTITY_OBJECT_ID=$(az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" \
  --query "identityProfile.kubeletidentity.objectId" -o tsv 2>/dev/null || echo "")
echo "==> kubelet identity clientId: ${KUBELET_IDENTITY_CLIENT_ID:-<not found>}"

# [ANSWER KEY - app-1]: The SecretProviderClass's keyvaultName field
# points at a Key Vault name that doesn't exist (a typo/placeholder, NOT
# the real ${KV_NAME} created above). The pod gets stuck ContainerCreating
# with a clear CSI mount error along the lines of "failed to get keyvault
# ... vault not found" — this is the most basic/obvious failure mode,
# good for confirming you know where to look (kubectl describe pod, or
# `kubectl get events` filtered to FailedMount) before moving to the
# subtler app-2/app-3.
cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: app-1-spc
  namespace: ${NS}
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "${KUBELET_IDENTITY_CLIENT_ID}"
    keyvaultName: "this-vault-does-not-exist"
    tenantId: "$(az account show --query tenantId -o tsv)"
    objects: |
      array:
        - |
          objectName: db-password
          objectType: secret
---
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
          image: nginx:1.25
          volumeMounts:
            - {name: secrets, mountPath: "/mnt/secrets", readOnly: true}
      volumes:
        - name: secrets
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes: {secretProviderClass: "app-1-spc"}
EOF

# [ANSWER KEY - app-2]: The SecretProviderClass correctly references the
# REAL Key Vault (${KV_NAME}) and the real secret name — but the
# identity was never granted permission to read it (no access policy /
# no "Key Vault Secrets User" RBAC role assignment for the kubelet
# identity on this vault). The mount fails with a 403 Forbidden /
# "Access Denied" from Key Vault itself — a completely different failure
# than app-1's "vault not found", even though both show up as a stuck
# pod. Distinguishing "the vault doesn't exist" from "the vault exists
# but I'm not allowed to read from it" is the actual skill here.
# Fix: az keyvault set-policy --name ${KV_NAME} --object-id <kubelet-identity-object-id> --secret-permissions get list
# (or the RBAC-permission-model equivalent: az role assignment create
# --role "Key Vault Secrets User" --assignee <object-id> --scope <vault-resource-id>)
cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: app-2-spc
  namespace: ${NS}
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "${KUBELET_IDENTITY_CLIENT_ID}"
    keyvaultName: "${KV_NAME}"
    tenantId: "$(az account show --query tenantId -o tsv)"
    objects: |
      array:
        - |
          objectName: db-password
          objectType: secret
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
    metadata: {labels: {app: app-2}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - {name: secrets, mountPath: "/mnt/secrets", readOnly: true}
      volumes:
        - name: secrets
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes: {secretProviderClass: "app-2-spc"}
EOF

echo "==> [app-2] kubelet identity Object ID (needed for the fix above): ${KUBELET_IDENTITY_OBJECT_ID:-<not found — check az aks show manually>}"

# [ANSWER KEY - app-3]: The vault reference is correct AND the identity
# has proper access (assuming app-2's fix was already applied, or you're
# testing this one on its own) — but this SecretProviderClass asks for
# an objectName that was never created in the vault ("api-key" was never
# set; only "db-password" exists). The failure is a clean "secret not
# found" from Key Vault itself, one level more specific than app-1's
# "vault not found" and completely different from app-2's "access
# denied" — three distinct, increasingly-specific failure points along
# the exact same request path (vault existence -> permission -> object
# existence), which is deliberately the pedagogical arc across all three
# of these.
cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: app-3-spc
  namespace: ${NS}
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "${KUBELET_IDENTITY_CLIENT_ID}"
    keyvaultName: "${KV_NAME}"
    tenantId: "$(az account show --query tenantId -o tsv)"
    objects: |
      array:
        - |
          objectName: api-key
          objectType: secret
---
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
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - {name: secrets, mountPath: "/mnt/secrets", readOnly: true}
      volumes:
        - name: secrets
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes: {secretProviderClass: "app-3-spc"}
EOF

echo ""
echo "==> Done. Day 18 issues created in namespace '${NS}'."
echo "==> Key Vault created: ${KV_NAME} (saved in /tmp/aks-day18-kv-name.txt for cleanup)"
echo "==> kubectl get pods -n ${NS}"
echo "==> kubectl describe pod <pod> -n ${NS}   # look for FailedMount events"
