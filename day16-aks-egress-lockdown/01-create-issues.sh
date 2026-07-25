#!/usr/bin/env bash
# day16-aks-egress-lockdown/01-create-issues.sh
# Namespace: aks-day16
#
# Theme: outbound-restricted / egress-locked-down AKS clusters — one of
# the most common real-world AKS support categories. A TRUE reproduction
# needs the cluster provisioned with outboundType=userDefinedRouting
# behind an Azure Firewall/NVA with specific FQDNs blocked — that's
# substantial additional infrastructure (firewall, route table, UDR) not
# practical to spin up unconditionally in a shared lab cluster already
# running with the default outboundType=loadBalancer.
#
# app-1 and app-3 SIMULATE the same symptom and diagnostic pattern using
# a Kubernetes NetworkPolicy instead of a real Azure Firewall — the
# debugging instinct you build (recognizing egress-blocked symptoms,
# knowing which FQDNs AKS actually requires) transfers directly even
# though the blocking mechanism here isn't the literal Azure one. app-2
# is a guided walkthrough for anyone who has (or wants to build) a real
# locked-down cluster.
#
# I have NOT been able to test this against a live Azure subscription.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="aks-day16"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Checking this cluster's actual outbound type..."
az aks show --resource-group aks-practice-rg --name aks-practice \
  --query "{outboundType:networkProfile.outboundType, loadBalancerSku:networkProfile.loadBalancerSku}" \
  -o table 2>/dev/null || echo "==> (couldn't query — check manually with 'az aks show ... --query networkProfile.outboundType')"

# [ANSWER KEY - app-1]: A default-deny-egress NetworkPolicy simulates
# what an Azure Firewall/NVA blocking required FQDNs looks like from
# inside a pod: image pulls that need to reach the registry over the
# network hang/timeout, NOT a clean "unauthorized" error like day11's ACR
# scenarios — this is a NETWORK-level failure, not an auth-level one,
# which is the key distinction to build intuition for. On a REAL
# outbound-restricted cluster, the actual fix is allow-listing the
# required FQDNs at the firewall (mcr.microsoft.com and
# *.data.mcr.microsoft.com at minimum, plus management.azure.com,
# login.microsoftonline.com, and others depending on enabled AKS
# features — see Microsoft's official "AKS outbound network and FQDN
# rules" documentation for the current authoritative list). Here, the
# fix is removing/adjusting the NetworkPolicy.
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
          image: mcr.microsoft.com/azure-cli:latest
          command: ["sleep", "infinity"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: simulated-firewall-lockdown
  namespace: ${NS}
spec:
  podSelector: {matchLabels: {app: app-1}}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector: {}   # allow DNS/in-cluster only
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
EOF

echo "==> [app-1] Try pulling/running a NEW image under this policy to see the timeout pattern:"
echo "    kubectl run test-pull --image=mcr.microsoft.com/dotnet/runtime:8.0 -n ${NS} --restart=Never"
echo "    kubectl describe pod test-pull -n ${NS}"

# [ANSWER KEY - app-2]: GUIDED MANUAL EXERCISE — if you have (or build) a
# real cluster with outboundType=userDefinedRouting behind an Azure
# Firewall, the classic incident is: everything worked at cluster
# creation, then weeks later a NEW feature gets enabled (e.g. Azure
# Policy add-on, Defender for Containers, a new ACR in a different
# region) that requires an FQDN nobody added to the firewall's allow
# list — nodes stay Ready and existing workloads keep running, but the
# NEW capability silently fails with timeouts that look identical to
# app-1's simulation above. Diagnose with:
#   az aks show --resource-group aks-practice-rg --name aks-practice --query networkProfile.outboundType
#   az network firewall application-rule list --collection-name <name> --firewall-name <fw> --resource-group <rg>
# Compare the allow-listed FQDNs against Microsoft's current "AKS
# outbound network and FQDN rules for cluster egress" documentation —
# the required list changes as Azure adds features, which is exactly why
# this bites people who set up firewall rules once and never revisit them.

# [ANSWER KEY - app-3]: Same simulated-lockdown mechanism as app-1, but
# targeting the credential/auth path specifically: a pod using Workload
# Identity (correctly labeled and configured — contrast with day11's
# app-2, where the LABEL itself was the bug) still fails to acquire a
# token, because egress to login.microsoftonline.com (Azure AD's token
# endpoint) is blocked. This is the trap: identity configuration can be
# 100% correct and it still won't work if the pod can't reach Azure AD
# over the network at all — two completely different root causes
# (day11's config gotcha vs. this network gotcha) that produce a similar
# symptom ("my Azure SDK calls fail to authenticate").
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
      containers:
        - name: app
          image: curlimages/curl:8.8.0
          command: ["sleep", "infinity"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-aad-endpoint
  namespace: ${NS}
spec:
  podSelector: {matchLabels: {app: app-3}}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector: {}
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
EOF

echo "==> [app-3] Verify the simulated block:"
echo "    kubectl exec -it deploy/app-3 -n ${NS} -- curl -sv --max-time 5 https://login.microsoftonline.com"
echo "    (should time out — that's the bug, standing in for a real firewall blocking this FQDN)"

echo ""
echo "==> Done. Day 16 issues created in namespace '${NS}'."
echo "==> app-1 and app-3 use a NetworkPolicy to SIMULATE egress lockdown (not a real"
echo "    Azure Firewall); app-2 is a guided walkthrough for a real locked-down cluster."
