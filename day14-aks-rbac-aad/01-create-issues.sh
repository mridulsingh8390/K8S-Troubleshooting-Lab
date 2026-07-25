#!/usr/bin/env bash
# day14-aks-rbac-aad/01-create-issues.sh
# Namespace: aks-day14
#
# Theme: Azure AD (Entra ID) integration with Kubernetes RBAC — failure
# modes that only exist because AKS layers Azure-side identity on top of
# Kubernetes' own RBAC model.
#
# I have NOT been able to test this against a live Azure subscription,
# and this topic in particular depends heavily on YOUR tenant's actual
# Azure AD groups/users, which I have no way to know. app-1 and app-2 are
# scripted as far as possible without real AAD group Object IDs; you'll
# need to substitute your own tenant's group Object ID to fully reproduce
# them. app-3 is fully self-contained (a local kubeconfig issue, not
# Azure-side) and needs no substitution.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="aks-day14"
AAD_GROUP_OBJECT_ID="00000000-0000-0000-0000-000000000000"   # <-- REPLACE with a real AAD group Object ID from your tenant to fully reproduce app-1/app-2

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: A RoleBinding references an Azure AD group by
# Object ID (the `name` field under subjects for kind: Group must be the
# AAD group's Object ID, not its display name). If that Object ID is
# stale — e.g. the AAD group was deleted and recreated, which generates
# a BRAND NEW Object ID even with the identical display name — the
# RoleBinding silently grants access to a group that no longer
# corresponds to anyone. `kubectl get rolebinding` shows everything
# looking correct; `kubectl auth can-i <verb> <resource> --as=<user-in-
# the-real-current-group>` still returns "no", with no error pointing at
# the actual cause. This deliberately uses a placeholder/invalid Object
# ID to demonstrate the shape of the bug — substitute a real stale ID
# from your tenant (or intentionally delete+recreate a test AAD group)
# to reproduce it exactly.
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: app-1-role, namespace: ${NS}}
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: app-1-binding, namespace: ${NS}}
subjects:
  - kind: Group
    name: "${AAD_GROUP_OBJECT_ID}"
    apiGroup: rbac.authorization.k8s.io
roleRef: {kind: Role, name: app-1-role, apiGroup: rbac.authorization.k8s.io}
EOF

echo "==> [app-1] Verify with (as a user who should be in the group):"
echo "    kubectl auth can-i list pods -n ${NS}"

# [ANSWER KEY - app-2]: GUIDED MANUAL EXERCISE — reproducing this exactly
# requires a cluster with "Azure RBAC for Kubernetes Authorization"
# enabled (a cluster-creation-time or later `az aks update
# --enable-azure-rbac` setting), which is a different mode from this
# lab's default cluster. In Azure RBAC mode, Kubernetes-native
# Role/RoleBinding objects are IGNORED ENTIRELY for authorization
# decisions — access is controlled purely by Azure RBAC role
# assignments (e.g. "Azure Kubernetes Service RBAC Reader") scoped to
# the cluster resource in Azure, assigned via `az role assignment
# create`. The trap: someone creates a perfectly correct Role +
# RoleBinding (like app-1 above) expecting it to grant access, and
# nothing happens — because on an Azure-RBAC-mode cluster, Kubernetes
# RBAC objects are simply not consulted at all. Diagnose by checking:
#   az aks show --resource-group aks-practice-rg --name aks-practice --query aadProfile.enableAzureRbac
# If enabling Azure RBAC on this cluster to practice this live, the fix
# is granting the correct Azure RBAC role assignment scoped to the
# namespace/cluster, not editing any Kubernetes RBAC object.

# [ANSWER KEY - app-3]: This one IS fully reproducible locally — no AAD
# group needed. `az aks get-credentials --admin` merges an
# admin/certificate-based kubeconfig context that BYPASSES Azure AD
# authentication entirely (it uses a local client cert directly, not
# your AAD token). If someone runs `--admin` once (often just trying to
# "make an auth problem go away"), kubectl silently keeps using that
# context afterward — every subsequent command succeeds using
# cluster-admin cert auth, masking whatever the real AAD/RBAC permission
# problem was, and giving a false sense that "RBAC is fine" when it was
# never actually tested.
echo "==> [app-3] This is a LOCAL kubeconfig issue, not something this script can"
echo "    'break' inside the cluster — reproduce it yourself:"
echo "    1. kubectl config get-contexts   # note your current (non-admin) context"
echo "    2. az aks get-credentials --resource-group aks-practice-rg --name aks-practice --admin"
echo "    3. kubectl config get-contexts   # a new '...-admin' context now exists"
echo "    4. kubectl config current-context   # check which one is now active"
echo "    Fix: kubectl config use-context <the-non-admin-context-name>"
echo "    to go back to testing through real AAD auth, and be deliberate about"
echo "    when '--admin' access is actually appropriate to use."

echo ""
echo "==> Done. Day 14 issues created in namespace '${NS}'."
echo "==> app-1 is scripted (needs a real AAD group Object ID substituted to fully"
echo "    reproduce); app-2 and app-3 are guided manual exercises — see the comments"
echo "    and echoed instructions above."
