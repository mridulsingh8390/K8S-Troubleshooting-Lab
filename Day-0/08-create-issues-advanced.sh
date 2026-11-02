#!/usr/bin/env bash
# 08-create-issues-advanced.sh
# Advanced troubleshooting scenarios: Storage, Scheduling, DNS, Rollouts,
# Multi-Attach, and StatefulSet storage issues.
# WARNING: Intentionally broken for practice. Use only in disposable Kind cluster.
# Usage: chmod +x 08-create-issues-advanced.sh && ./08-create-issues-advanced.sh

set -euo pipefail

kubectl create namespace advanced --dry-run=client -o yaml | kubectl apply -f -

echo "==> Seeding ADVANCED namespace with 10 complex issues (app-11..app-20)..."

# ============================================================
# [app-11] PVC Pending - No StorageClass exists in cluster
# PVC requests "fast-ssd" class which was never created
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-11-pvc
  namespace: advanced
spec:
  storageClassName: fast-ssd
  accessModes: ["ReadWriteOnce"]
  resources:
    requests: {storage: 1Gi}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-11
  namespace: advanced
spec:
  replicas: 1
  selector: {matchLabels: {app: app-11}}
  template:
    metadata: {labels: {app: app-11}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: app-11-pvc
EOF

# ============================================================
# [app-12] Multi-Attach Error - RWO PVC used by Deployment with 2 replicas
# Kind's default StorageClass is RWO; 2nd pod on different node fails attach
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-12-pvc
  namespace: advanced
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests: {storage: 1Gi}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-12
  namespace: advanced
spec:
  replicas: 2  # Multi-Attach error: RWO volume cannot attach to 2 nodes
  selector: {matchLabels: {app: app-12}}
  template:
    metadata: {labels: {app: app-12}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: app-12-pvc
EOF

# ============================================================
# [app-13] Pod Pending - Node affinity requires non-existent label
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-13
  namespace: advanced
spec:
  replicas: 1
  selector: {matchLabels: {app: app-13}}
  template:
    metadata: {labels: {app: app-13}}
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/os
                    operator: In
                    values: ["windows"]  # No Windows nodes in cluster
      containers:
        - name: app
          image: nginx:1.25
EOF

# ============================================================
# [app-14] Pod Pending - Node taint without toleration
# Control-plane has taint; this pod targets it specifically without toleration
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-14
  namespace: advanced
spec:
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""  # Targets control-plane
  containers:
    - name: app
      image: nginx:1.25
  # Missing toleration for node-role.kubernetes.io/control-plane:NoSchedule
EOF

# ============================================================
# [app-15] DNS Failure - Pod uses wrong DNS policy pointing to bad nameserver
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-15
  namespace: advanced
spec:
  dnsPolicy: None
  dnsConfig:
    nameservers:
      - 192.0.2.100  # Non-existent DNS server (RFC 5737 test IP)
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "nslookup kubernetes.default.svc.cluster.local || sleep 3600"]
EOF

# ============================================================
# [app-16] Rollout Stuck - Deployment updated with non-existent image tag
# Creates a ReplicaSet that cannot pull, blocking the rollout
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-16
  namespace: advanced
spec:
  replicas: 2
  selector: {matchLabels: {app: app-16}}
  template:
    metadata: {labels: {app: app-16}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
EOF

# Simulate a bad update (this will create a new ReplicaSet with ImagePullBackOff)
kubectl set image deployment/app-16 app=nginx:broken-tag-12345 -n advanced

# ============================================================
# [app-17] StatefulSet PVC Mismatch - Orphaned PVC from previous scale-up
# Manually create a PVC with wrong name pattern, StatefulSet expects different one
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app-17-headless
  namespace: advanced
spec:
  clusterIP: None
  selector: {app: app-17}
  ports: [{port: 80}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: app-17
  namespace: advanced
spec:
  serviceName: app-17-headless
  replicas: 1
  selector: {matchLabels: {app: app-17}}
  template:
    metadata: {labels: {app: app-17}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests: {storage: 1Gi}
EOF

# Create a conflicting PVC manually (simulates leftover from previous deployment)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-app-17-0
  namespace: advanced
  labels: {app: app-17}
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests: {storage: 5Gi}  # Different size than template (1Gi)
  storageClassName: standard
EOF

# ============================================================
# [app-18] HostPort Conflict - Two pods trying to bind same host port on same node
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-18
  namespace: advanced
spec:
  replicas: 2
  selector: {matchLabels: {app: app-18}}
  template:
    metadata: {labels: {app: app-18}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          ports:
            - containerPort: 80
              hostPort: 18080  # Both pods will try to bind 18080 on nodes
EOF

# ============================================================
# [app-19] ConfigMap Rollout Failure - Immutable ConfigMap update attempt
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-19-config
  namespace: advanced
data:
  app.conf: "max_connections=100"
immutable: true
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-19
  namespace: advanced
spec:
  replicas: 1
  selector: {matchLabels: {app: app-19}}
  template:
    metadata: {labels: {app: app-19}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - name: config
              mountPath: /etc/config
      volumes:
        - name: config
          configMap:
            name: app-19-config
EOF

# Attempt to update immutable ConfigMap (will fail)
kubectl patch configmap app-19-config -n advanced --type merge -p '{"data":{"app.conf":"max_connections=200"}}' || true

# ============================================================
# [app-20] Service DNS Mismatch - Service name doesn't match DNS expected by app
# App tries to reach "db-service" but actual service is "database-svc"
# ============================================================
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-20-db
  namespace: advanced
spec:
  replicas: 1
  selector: {matchLabels: {app: app-20-db}}
  template:
    metadata: {labels: {app: app-20-db}}
    spec:
      containers:
        - name: db
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: database-svc  # Wrong name: app expects "db-service"
  namespace: advanced
spec:
  selector: {app: app-20-db}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: v1
kind: Pod
metadata:
  name: app-20-client
  namespace: advanced
spec:
  containers:
    - name: client
      image: busybox:1.36
      command: ["sh", "-c", "wget -qO- http://db-service/ || echo 'DNS lookup failed'; sleep 3600"]
EOF

echo ""
echo "==> Advanced issue lab created. Inspect with:"
echo "    kubectl get pods,pvc,svc,deploy -n advanced"
echo "    kubectl describe pod <pod> -n advanced"
echo ""
echo "==> Quick checks:"
echo "    kubectl get pvc -n advanced                    # app-11 Pending, app-12 Bound"
echo "    kubectl get pods -n advanced -o wide           # app-12 Multi-Attach, app-13/14 Pending"
echo "    kubectl rollout status deployment/app-16 -n advanced  # Stuck rollout"
echo "    kubectl logs app-15 -n advanced                # DNS errors"
echo "    kubectl get endpoints -n advanced              # app-20 empty endpoints"