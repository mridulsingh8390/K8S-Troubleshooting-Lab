#!/usr/bin/env bash
# day12-aks-storage-csi/01-create-issues.sh
# Namespace: aks-day12
#
# Theme: Azure Disk/Azure File CSI driver failures specific to AKS —
# zone affinity, SKU/VM-size mismatches, and storage account networking.
#
# I have NOT been able to test this against a live Azure subscription.
# Zone names, VM SKU capabilities, and exact CSI error text can vary by
# region/subscription — treat this as a strong starting point, verify
# against your actual region's zone/VM-size support before assuming a
# result means what the comment says it should.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="aks-day12"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Checking available zones for the managed-csi-premium StorageClass..."
kubectl get storageclass managed-csi-premium -o yaml 2>/dev/null | head -20 || \
  echo "==> NOTE: 'managed-csi-premium' StorageClass not found — this AKS version/region may name it differently (check 'kubectl get sc')."

# [ANSWER KEY - app-1]: The PVC requests the Premium_LRS-backed
# StorageClass, but the Deployment's nodeSelector pins it to
# "kubernetes.io/os: linux" plus a VM-size label that (on many smaller
# Azure VM SKUs, e.g. some B-series burstable VMs) does not support
# Premium SSD attachment. The PVC may bind, but the pod gets stuck
# ContainerCreating/Pending with an Azure Disk attach error referencing
# unsupported disk performance tier for the VM size. Fix: either use a
# StorageClass backed by Standard_LRS/StandardSSD_LRS, or move the
# workload to a node pool with a VM size that supports Premium disks.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-1
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: managed-csi-premium
  resources: {requests: {storage: 10Gi}}
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
          volumeMounts: [{name: data, mountPath: /data}]
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: pvc-1}
EOF

# [ANSWER KEY - app-2]: An Azure Disk PVC gets dynamically provisioned in
# whichever zone its first-scheduled pod lands in (Azure Disk is
# zone-bound, unlike Azure Files). If that Deployment is later scaled
# down and a replacement pod gets scheduled onto a node in a DIFFERENT
# availability zone (which the scheduler has no reason to avoid unless
# told to), the pod gets stuck with a "volume node affinity conflict" —
# the disk physically cannot attach to a node outside its zone. Fix:
# either pin the workload's nodeSelector/affinity to a specific zone
# matching the disk, or use Azure Files (zone-agnostic, ReadWriteMany)
# if cross-zone flexibility is actually required.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-2
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: managed-csi
  resources: {requests: {storage: 5Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-2
  namespace: ${NS}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app: app-2}}
  template:
    metadata: {labels: {app: app-2}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts: [{name: data, mountPath: /data}]
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: pvc-2}
EOF

echo "==> [app-2] To actually reproduce the zone conflict: note which zone the current"
echo "    pod/node is in, then cordon that node and delete the pod so it reschedules"
echo "    elsewhere — kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone"

# [ANSWER KEY - app-3]: The Azure File Storage Account has network rules
# restricting access to specific subnets/IPs, and the AKS subnet was
# never added to the storage account's allow-list (no private endpoint
# and no service endpoint configured). The PVC binds fine (provisioning
# is an ARM/control-plane operation), but the actual pod mount fails —
# "MountVolume.SetUp failed" / "permission denied" mounting the SMB
# share, because the DATA PLANE connection from the node to the storage
# account is what's being blocked, not anything Kubernetes-level. Fix:
# add the AKS subnet to the storage account's network rules (or a
# private endpoint), via:
#   az storage account network-rule add --account-name <name> \\
#     --resource-group ${NS%%-*}... --subnet <aks-subnet-resource-id>
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-3
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteMany"]
  storageClassName: azurefile-csi
  resources: {requests: {storage: 5Gi}}
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
          volumeMounts: [{name: data, mountPath: /data}]
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: pvc-3}
EOF
echo "==> [app-3] This scenario requires the underlying storage account to actually have"
echo "    restrictive network rules applied — 'azurefile-csi' provisions a new storage"
echo "    account per PVC by default, which starts network-open. To truly reproduce this,"
echo "    find the auto-created storage account (az storage account list -g MC_<rg>_<cluster>_<region>)"
echo "    and apply a restrictive network rule to it yourself, OR use a pre-existing"
echo "    storage account + static PV referencing it with rules already applied."

echo ""
echo "==> Done. Day 12 issues created in namespace '${NS}'."
echo "==> kubectl get pvc,pods -n ${NS}"
