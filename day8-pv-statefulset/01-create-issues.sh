#!/usr/bin/env bash
# day8-pv-statefulset/01-create-issues.sh
# Namespace: day8 (plus 3 cluster-scoped PersistentVolumes — PVs are NOT
# namespaced, so they aren't cleaned up by deleting the namespace alone;
# 02-cleanup-namespace.sh in this folder handles that).
#
# Theme: static PV/PVC provisioning and StatefulSet lifecycle — deeper
# than Day 2's dynamic-provisioning storage issues.
#
# All resources are named app-1..app-5. Comments are the answer key —
# avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day8"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: A PV exists with the right StorageClass, size, and
# access mode — but the PVC's selector asks for label "tier: silver" while
# the PV is labeled "tier: gold". PVC binding requires the selector to
# match, so this stays Pending even though a PV that "should" fit exists.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-1
  labels: {tier: gold}
spec:
  capacity: {storage: 1Gi}
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual-day8
  hostPath: {path: /tmp/day8-pv-1}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-1
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual-day8
  resources: {requests: {storage: 1Gi}}
  selector:
    matchLabels: {tier: silver}
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

# [ANSWER KEY - app-2]: A PV with reclaimPolicy Retain is bound to a PVC,
# then that PVC is deleted (simulating an operator mistake) — the PV
# doesn't get cleaned up or made Available again; it sits in "Released"
# state holding a stale claimRef. A brand new PVC asking for the same
# StorageClass/size can't bind to it (it's not Available), so app-2 gets
# stuck Pending until someone manually clears the PV's claimRef (or
# deletes and recreates the PV) — the real-world "why won't my volume get
# reused" gotcha.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-2
spec:
  capacity: {storage: 1Gi}
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual-day8-retain
  hostPath: {path: /tmp/day8-pv-2}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-2-original
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual-day8-retain
  resources: {requests: {storage: 1Gi}}
EOF

echo "==> [app-2] Waiting for pvc-2-original to bind to pv-2..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/pvc-2-original -n "${NS}" --timeout=60s || true

echo "==> [app-2] Deleting pvc-2-original to simulate an accidental delete (pv-2 will go 'Released')..."
kubectl delete pvc pvc-2-original -n "${NS}" --ignore-not-found

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-2
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual-day8-retain
  resources: {requests: {storage: 1Gi}}
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
          volumeMounts: [{name: data, mountPath: /data}]
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: pvc-2}
EOF

# [ANSWER KEY - app-3]: The only PV offering StorageClass
# "manual-day8-small" has just 500Mi capacity, but the PVC requests 2Gi.
# No StorageClass object exists to dynamically provision more, so the PVC
# just sits Pending waiting for a PV that's big enough.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-3
spec:
  capacity: {storage: 500Mi}
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual-day8-small
  hostPath: {path: /tmp/day8-pv-3}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-3
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual-day8-small
  resources: {requests: {storage: 2Gi}}
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

# [ANSWER KEY - app-4]: The StatefulSet was created with
# updateStrategy.rollingUpdate.partition: 2 already baked in (a leftover
# from a previous careful/canary rollout that never got reset to 0).
# After creation, the image gets patched to a new tag — but with
# partition: 2, ONLY pods with ordinal >= 2 (just app-4-2) actually get
# updated. app-4-0 and app-4-1 silently stay on the old image, which
# looks like a "stuck" or "half-finished" rollout if you don't know to
# check the partition value.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app-4
  namespace: ${NS}
spec:
  clusterIP: None
  selector: {app: app-4}
  ports: [{port: 80}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: app-4
  namespace: ${NS}
spec:
  serviceName: app-4
  replicas: 3
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 2
  selector: {matchLabels: {app: app-4}}
  template:
    metadata: {labels: {app: app-4}}
    spec:
      containers:
        - name: app
          image: nginx:1.24
EOF

echo "==> [app-4] Waiting for the StatefulSet to reach 3/3 before simulating the update..."
kubectl rollout status statefulset/app-4 -n "${NS}" --timeout=120s || true

echo "==> [app-4] Patching image to nginx:1.25 (simulating 'we shipped an update')..."
kubectl set image statefulset/app-4 app=nginx:1.25 -n "${NS}"

# [ANSWER KEY - app-5]: podManagementPolicy defaults to OrderedReady,
# which means pod-1 is never even CREATED until pod-0 is Running AND
# Ready. This StatefulSet's readinessProbe deliberately fails only for
# the pod whose hostname is "app-5-0" (checked via the pod's own
# hostname, which StatefulSets set deterministically) — so pod-0 never
# becomes Ready, and pod-1/pod-2 are stuck waiting behind it forever.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app-5
  namespace: ${NS}
spec:
  clusterIP: None
  selector: {app: app-5}
  ports: [{port: 80}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: app-5
  namespace: ${NS}
spec:
  serviceName: app-5
  replicas: 3
  podManagementPolicy: OrderedReady
  selector: {matchLabels: {app: app-5}}
  template:
    metadata: {labels: {app: app-5}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          readinessProbe:
            exec:
              command: ["sh", "-c", "[ \"\$(hostname)\" != \"app-5-0\" ]"]
            periodSeconds: 5
EOF

echo ""
echo "==> Done. Day 8 issues created in namespace '${NS}' (app-1..app-5)."
echo "==> Note: pv-1, pv-2, pv-3 are CLUSTER-SCOPED — use this folder's"
echo "    02-cleanup-namespace.sh (not a plain namespace delete) to remove them too."
echo "==> kubectl get pv,pvc,deploy,sts,pods -n ${NS}"
