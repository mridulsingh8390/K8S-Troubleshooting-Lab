#!/usr/bin/env bash
# day17-aks-snat-loadbalancer/01-create-issues.sh
# Namespace: aks-day17
#
# Theme: Azure Load Balancer Service provisioning and SNAT port
# exhaustion — outbound connectivity failures that look like "flaky
# external dependencies" rather than an obvious cluster misconfiguration.
#
# I have NOT been able to test this against a live Azure subscription.
# Genuinely triggering real SNAT exhaustion requires sustained high
# connection volume against a real backend — not something to script
# blindly at full scale. app-2 below is a small, illustrative version of
# the MECHANISM, clearly not a guaranteed real exhaustion trigger; the
# diagnostic pattern (checking the SNATConnectionCount metric) is the
# actual lesson.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="aks-day17"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: The Service requests a specific static
# loadBalancerIP that was never reserved/allocated in this resource
# group (a placeholder/made-up IP). The Service stays EXTERNAL-IP
# <pending> forever — `kubectl describe service` won't show much, but
# `kubectl get events -n aks-day17` (or the cloud-controller-manager
# logs) will show the Azure cloud provider failing to find/assign that
# IP. This is a very common copy-paste mistake: reusing an IP from a
# different environment/resource group without actually provisioning a
# matching Azure Public IP resource first.
# Fix: either remove loadBalancerIP (let Azure assign one automatically),
# or first create a real static Public IP with
# `az network public-ip create` and reference ITS actual address.
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
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: app-1
  namespace: ${NS}
spec:
  type: LoadBalancer
  loadBalancerIP: "20.99.99.99"
  selector: {app: app-1}
  ports: [{port: 80, targetPort: 80}]
EOF

echo "==> [app-1] Watch it stay pending:"
echo "    kubectl get svc app-1 -n ${NS} -w"

# [ANSWER KEY - app-2]: A small-scale illustration of SNAT port
# exhaustion — this Deployment opens many rapid, short-lived outbound
# connections to an external endpoint. At real production scale (many
# replicas, sustained high connection churn, especially many short-lived
# connections to the SAME destination IP:port, which is the worst case
# for SNAT port reuse), the Standard Load Balancer's default outbound
# rule can run out of ephemeral SNAT ports, causing intermittent
# "connection failed"/timeout errors that have NOTHING to do with the
# destination service being unhealthy. At this small scale you likely
# won't exhaust anything — the point is the pattern and the metric to
# check, not guaranteed reproduction:
#   az monitor metrics list --resource <load-balancer-resource-id> \\
#     --metric SNATConnectionCount --interval PT1M
# Fix (on a real cluster hitting this): increase
# `--load-balancer-managed-outbound-ip-count` (more IPs = more available
# SNAT ports), or switch to a NAT Gateway for outbound traffic instead of
# the Load Balancer's default outbound rule (NAT Gateway has a much
# larger practical SNAT port budget).
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-2
  namespace: ${NS}
spec:
  replicas: 3
  selector: {matchLabels: {app: app-2}}
  template:
    metadata: {labels: {app: app-2}}
    spec:
      containers:
        - name: app
          image: curlimages/curl:8.8.0
          command:
            - sh
            - -c
            - |
              while true; do
                curl -s -o /dev/null --max-time 2 https://mcr.microsoft.com/ || true
              done
EOF

echo "==> [app-2] This generates connection churn but at a scale unlikely to actually"
echo "    exhaust SNAT ports on its own — it's here to demonstrate the PATTERN and give"
echo "    you something to point the SNATConnectionCount metric query at. Scale replicas"
echo "    up substantially if you want to push harder (mind the cost/blast radius)."

# [ANSWER KEY - app-3]: The Service annotation
# "service.beta.kubernetes.io/azure-load-balancer-internal: \"true\""
# means Azure provisions this LoadBalancer with a PRIVATE (internal VNet)
# IP, not a public one — but nothing else about the manifest signals
# that. Someone expecting a public-facing IP (e.g. because the Service
# TYPE says LoadBalancer, which "sounds public") will be confused why
# external/internet traffic can't reach it — EXTERNAL-IP shows a real IP
# address, it's just not routable from outside the VNet. This is purely
# an annotation people miss when reading the manifest, not an error
# state at all from Kubernetes' or Azure's perspective — both did exactly
# what was asked.
# Fix: remove the internal annotation if public access was actually
# intended, or update expectations/DNS/docs if internal access was
# correct all along and the confusion is just about what "LoadBalancer"
# implies.
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
kind: Service
metadata:
  name: app-3
  namespace: ${NS}
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  selector: {app: app-3}
  ports: [{port: 80, targetPort: 80}]
EOF

echo "==> [app-3] Check what kind of IP it actually got:"
echo "    kubectl get svc app-3 -n ${NS} -o wide"
echo "    kubectl get svc app-3 -n ${NS} -o jsonpath='{.metadata.annotations}'"

echo ""
echo "==> Done. Day 17 issues created in namespace '${NS}'."
echo "==> kubectl get svc -n ${NS}"
