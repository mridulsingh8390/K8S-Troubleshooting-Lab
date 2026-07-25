#!/usr/bin/env bash
# day15-aks-autoscaler-nodepools/01-create-issues.sh
# Namespace: aks-day15
#
# Theme: cluster autoscaler and node pool behavior specific to AKS —
# these all depend on scale limits and taints configured at the Azure
# level, not just the Kubernetes object level.
#
# I have NOT been able to test this against a live Azure subscription.
# Node pool creation takes real time (several minutes) and costs money
# for the extra VMs — this script creates one additional small node pool
# for app-2/app-3. Review before running.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
RESOURCE_GROUP="aks-practice-rg"
CLUSTER_NAME="aks-practice"
NS="aks-day15"
NODEPOOL_NAME="day15pool"

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Enabling cluster autoscaler on the default node pool (min 1, max 2)..."
az aks nodepool update \
  --resource-group "${RESOURCE_GROUP}" \
  --cluster-name "${CLUSTER_NAME}" \
  --name nodepool1 \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 2 \
  --output none || echo "==> NOTE: nodepool name may differ from 'nodepool1' on your cluster — check 'az aks nodepool list' and adjust."

# [ANSWER KEY - app-1]: The autoscaler's max-count on the default pool is
# capped at 2 (set above). This Deployment requests far more replicas
# than 2 nodes can hold — pods stay Pending, but the autoscaler does NOT
# add a 3rd node, because it's already at its configured ceiling. The
# scheduler events will show "Insufficient cpu"/"Insufficient memory",
# which looks identical to a cluster with autoscaler disabled entirely —
# you have to specifically check the node pool's max-count to realize
# scaling is capped, not broken.
# Fix: az aks nodepool update --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name nodepool1 --update-cluster-autoscaler --max-count 5
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-1
  namespace: ${NS}
spec:
  replicas: 20
  selector: {matchLabels: {app: app-1}}
  template:
    metadata: {labels: {app: app-1}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          resources:
            requests: {cpu: "500m", memory: "256Mi"}
EOF

echo "==> Creating a dedicated, tainted node pool for app-2/app-3 (this takes a few minutes)..."
if az aks nodepool show --resource-group "${RESOURCE_GROUP}" --cluster-name "${CLUSTER_NAME}" --name "${NODEPOOL_NAME}" &>/dev/null; then
  echo "==> Node pool '${NODEPOOL_NAME}' already exists, skipping creation."
else
  az aks nodepool add \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${NODEPOOL_NAME}" \
    --node-count 1 \
    --node-taints "dedicated=day15:NoSchedule" \
    --labels "dedicated=day15" \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 2 \
    --output none
fi

# [ANSWER KEY - app-2]: The dedicated node pool was created WITH a taint
# (dedicated=day15:NoSchedule), but this Deployment has no matching
# toleration. The pods stay Pending forever on the default pool instead
# (or don't schedule onto the new pool at all) — and critically, the
# cluster autoscaler will NOT scale up the tainted pool for these pods,
# because they were never actually asking to run there in the first
# place (no toleration = the scheduler doesn't even consider that pool a
# candidate). This looks like "the new node pool isn't being used by the
# autoscaler," when actually the workload was never eligible for it.
# Fix: add the matching toleration to the pod spec.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-2
  namespace: ${NS}
spec:
  replicas: 2
  selector: {matchLabels: {app: app-2}}
  template:
    metadata: {labels: {app: app-2}}
    spec:
      nodeSelector:
        dedicated: day15
      containers:
        - name: app
          image: nginx:1.25
EOF

# [ANSWER KEY - app-3]: This pod has the CORRECT toleration and lands on
# the dedicated pool fine — but it's also annotated
# "cluster-autoscaler.kubernetes.io/safe-to-evict: \"false\"". Even when
# the pool is underutilized and the autoscaler would otherwise want to
# scale down and consolidate, it will NEVER evict this pod to do so —
# scale-down is permanently blocked on any node hosting it. This looks
# like "my node count never goes down even though nothing is really
# running," and the annotation is easy to miss since it doesn't show up
# in `kubectl get pods` output at all (only `describe` or `-o yaml`).
# Fix: remove the annotation if eviction is actually safe for this
# workload, or use a PodDisruptionBudget instead if you need SOME control
# over eviction rather than blocking it outright.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-3
  namespace: ${NS}
  annotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
spec:
  tolerations:
    - key: dedicated
      operator: Equal
      value: day15
      effect: NoSchedule
  nodeSelector:
    dedicated: day15
  containers:
    - name: app
      image: nginx:1.25
EOF

echo ""
echo "==> Done. Day 15 issues created in namespace '${NS}'."
echo "==> kubectl get pods -n ${NS} -o wide"
echo "==> az aks nodepool list --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --output table"
