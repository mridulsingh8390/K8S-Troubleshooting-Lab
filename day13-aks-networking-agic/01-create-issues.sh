#!/usr/bin/env bash
# day13-aks-networking-agic/01-create-issues.sh
# Namespace: aks-day13
#
# Theme: Azure CNI subnet IP exhaustion, Application Gateway Ingress
# Controller (AGIC), and network policy engine confusion — all specific
# to how AKS networking differs from a generic cluster.
#
# I have NOT been able to test this against a live Azure subscription,
# and AGIC in particular requires its own add-on/Application Gateway
# resource that this script does not fully provision (that's a
# significant amount of additional Azure infrastructure). Where full
# automation isn't practical, this script sets up what it can and
# documents the rest as a guided manual exercise.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="aks-day13"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: Azure CNI (in its default, non-"CNI Overlay"
# mode) assigns each pod a real IP from the node's VNet subnet, and each
# node reserves enough IPs up front for its configured --max-pods value
# — NOT just however many pods actually exist. If the subnet is small
# relative to (max-pods x node count), you can run out of assignable IPs
# well before you run out of CPU/memory capacity, and new pods get stuck
# Pending/ContainerCreating with IP allocation failures in kubelet/CNI
# logs. This Deployment intentionally requests a high replica count to
# try to trigger that on a small subnet. On a larger subnet this may
# simply succeed — if so, the exercise is to calculate your subnet's
# actual IP budget (subnet size minus Azure-reserved IPs, divided by
# max-pods per node) and reason about the ceiling rather than to
# necessarily hit it live.
# Fix (if hit): reduce --max-pods on the node pool, use a larger subnet,
# or switch to Azure CNI Overlay mode (pods get IPs from a separate
# overlay space, not the VNet subnet).
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-1
  namespace: ${NS}
spec:
  replicas: 50
  selector: {matchLabels: {app: app-1}}
  template:
    metadata: {labels: {app: app-1}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          resources:
            requests: {cpu: "10m", memory: "16Mi"}
EOF

echo "==> [app-1] Check for IP-allocation-related events with:"
echo "    kubectl get events -n ${NS} --field-selector reason=FailedCreatePodSandBox"
echo "    kubectl describe nodes | grep -A3 'Allocatable\\|pods'"

# [ANSWER KEY - app-2]: GUIDED MANUAL EXERCISE — full automation would
# require provisioning an actual Application Gateway + enabling the AGIC
# add-on, which is significant additional infrastructure. If you have
# AGIC enabled on this cluster (az aks addon enable --addons
# ingress-appgw ...), the classic failure mode is: the Application
# Gateway's dedicated subnet doesn't have an NSG rule allowing inbound
# traffic on ports 65200-65535 (required for AGIC's own health probes
# from the Azure infrastructure), so AGIC can create the Ingress'
# listener/backend-pool configuration but the Application Gateway
# reports the backend as Unhealthy and external traffic never reaches
# your pods — even though `kubectl get ingress` shows everything as
# expected. To practice this: create an Ingress resource with
# `kubernetes.io/ingress.class: azure/application-gateway`, then check
# the Application Gateway's backend health in the Azure Portal or via
# `az network application-gateway show-backend-health`.

# [ANSWER KEY - app-3]: A NetworkPolicy is applied expecting default-deny
# behavior, but this lab's own 00-setup-cluster.sh creates the AKS
# cluster WITHOUT specifying --network-policy, so no network policy
# engine is enabled by default. In that state, NetworkPolicy objects
# apply into the API but are silently NOT ENFORCED at all — curl
# succeeds across pods that should be blocked, with zero errors
# anywhere. This is the most dangerous kind of failure: it looks like a
# working security control that simply never fires. Network policy
# engine choice on AKS is only configurable at cluster CREATE time, not
# changeable in-place afterward — verify what's active with:
#   az aks show --resource-group aks-practice-rg --name aks-practice --query networkProfile.networkPolicy
# Fix: this specific cluster would need to be recreated with
# --network-policy azure (or cilium/calico) to actually enforce
# NetworkPolicy objects — there's no in-place upgrade path.
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
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Pod
metadata:
  name: curl-debug
  namespace: ${NS}
  labels: {app: curl-debug}
spec:
  containers:
    - name: curl
      image: curlimages/curl:8.8.0
      command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-app-3
  namespace: ${NS}
spec:
  podSelector: {matchLabels: {app: app-3}}
  policyTypes: ["Ingress"]
  ingress: []
EOF

echo ""
echo "==> Done. Day 13 issues created in namespace '${NS}'."
echo "==> app-1 is fully scripted; app-2 is a guided manual exercise (needs AGIC pre-installed);"
echo "==> app-3 is fully scripted — test with:"
echo "    kubectl exec -it curl-debug -n ${NS} -- curl -sv --max-time 5 http://app-3"
echo "    (a 'deny-app-3' policy exists, so a SUCCESSFUL curl here IS the bug on a"
echo "    non-network-policy-enforcing cluster — the policy should have blocked it)"
