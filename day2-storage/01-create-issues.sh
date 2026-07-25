#!/usr/bin/env bash
# day2-storage/01-create-issues.sh
# Namespace: day2
# Theme: storage & persistence failures (PVC binding, node affinity of
# local volumes, emptyDir limits, read-only volume writes).
#
# All resources are named app-1..app-5. Comments are the answer key —
# avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day2"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: PVC stuck Pending — storageClassName is explicitly
# set to "" (empty string), which means "only bind to a pre-existing
# PersistentVolume", but no matching PV exists. (Different from asking for
# a StorageClass that doesn't exist — this asks for NO StorageClass at all.)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-1
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ""
  resources:
    requests: {storage: 1Gi}
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

# [ANSWER KEY - app-2]: StatefulSet PVCs stuck Pending — requests
# ReadWriteMany, which the default local-path StorageClass in this cluster
# cannot provision (it only supports ReadWriteOnce).
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: app-2
  namespace: ${NS}
spec:
  serviceName: app-2
  replicas: 1
  selector: {matchLabels: {app: app-2}}
  template:
    metadata: {labels: {app: app-2}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts: [{name: data, mountPath: /usr/share/nginx/html}]
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteMany"]
        resources: {requests: {storage: 1Gi}}
EOF

# [ANSWER KEY - app-3]: Second replica stuck Pending with
# "volume node affinity conflict" — the local-path provisioner binds a
# volume to whichever single node first claims it; a second replica of the
# same PVC can't schedule onto a different node.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-3
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  resources: {requests: {storage: 1Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-3
  namespace: ${NS}
spec:
  replicas: 2
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

# [ANSWER KEY - app-4]: Pod gets Evicted — emptyDir has a sizeLimit of 50Mi,
# and the container writes a file larger than that limit.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-4
  namespace: ${NS}
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "dd if=/dev/zero of=/data/bigfile bs=1M count=100; sleep infinity"]
      volumeMounts: [{name: scratch, mountPath: /data}]
  volumes:
    - name: scratch
      emptyDir: {sizeLimit: "50Mi"}
EOF

# [ANSWER KEY - app-5]: CrashLoopBackOff — ConfigMap volumes are always
# mounted read-only; the container command tries to write into that mount
# and fails.
kubectl create configmap config-5 -n "${NS}" \
  --from-literal=app.conf="listen 80;" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-5
  namespace: ${NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: app-5}}
  template:
    metadata: {labels: {app: app-5}}
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "touch /etc/app/newfile.conf; sleep infinity"]
          volumeMounts: [{name: conf, mountPath: /etc/app}]
      volumes:
        - name: conf
          configMap: {name: config-5}
EOF

echo ""
echo "==> Done. Day 2 issues created in namespace '${NS}' (app-1..app-5)."
echo "==> kubectl get deploy,sts,pvc,pods -n ${NS}"
