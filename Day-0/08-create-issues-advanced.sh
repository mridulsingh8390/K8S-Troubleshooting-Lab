#!/usr/bin/env bash
# 10-create-all-issues.sh
# Complete troubleshooting lab: Creates all 20 broken scenarios
# qa namespace:        app-1 to app-10  (Basic issues)
# advanced namespace:  app-11 to app-20 (Advanced issues)
# WARNING: Intentionally broken for practice. Use only in disposable Kind cluster.
# Usage: chmod +x 10-create-all-issues.sh && ./10-create-all-issues.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Kubernetes Troubleshooting Lab Setup${NC}"
echo -e "${GREEN}  Creating 20 broken scenarios...${NC}"
echo -e "${GREEN}========================================${NC}"

# Create namespaces
echo -e "\n${YELLOW}==> Creating namespaces...${NC}"
kubectl create namespace qa --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace advanced --dry-run=client -o yaml | kubectl apply -f -

# ============================================================
# QA NAMESPACE - BASIC ISSUES (app-1 to app-10)
# ============================================================
echo -e "\n${YELLOW}==> Seeding QA namespace with basic issues (app-1..app-10)...${NC}"

# [app-1] CreateContainerConfigError - Secret key mismatch
kubectl create secret generic secret-1 -n qa \
  --from-literal=db_username=admin \
  --from-literal=db_password=supersecret \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-1
  namespace: qa
spec:
  replicas: 1
  selector: {matchLabels: {app: app-1}}
  template:
    metadata: {labels: {app: app-1}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          env:
            - name: DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: secret-1
                  key: username
EOF

# [app-2] ImagePullBackOff - Bad image tag
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-2
  namespace: qa
spec:
  replicas: 1
  selector: {matchLabels: {app: app-2}}
  template:
    metadata: {labels: {app: app-2}}
    spec:
      containers:
        - name: app
          image: nginx:this-tag-does-not-exist
EOF

# [app-3] CrashLoopBackOff - Command exits immediately
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-3
  namespace: qa
spec:
  replicas: 1
  selector: {matchLabels: {app: app-3}}
  template:
    metadata: {labels: {app: app-3}}
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "echo 'starting up'; exit 1"]
EOF

# [app-4] Pending - Insufficient resources
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-4
  namespace: qa
spec:
  replicas: 1
  selector: {matchLabels: {app: app-4}}
  template:
    metadata: {labels: {app: app-4}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          resources:
            requests:
              cpu: "32"
              memory: "128Gi"
EOF

# [app-5] Running but not Ready - Bad readiness probe
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-5
  namespace: qa
spec:
  replicas: 1
  selector: {matchLabels: {app: app-5}}
  template:
    metadata: {labels: {app: app-5}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          ports: [{containerPort: 80}]
          readinessProbe:
            httpGet:
              path: /this-path-does-not-exist
              port: 80
            periodSeconds: 5
EOF

# [app-6] StatefulSet PVC Pending - Bad StorageClass
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: app-6-headless
  namespace: qa
spec:
  clusterIP: None
  selector: {app: app-6}
  ports: [{port: 80}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: app-6
  namespace: qa
spec:
  serviceName: app-6-headless
  replicas: 2
  selector: {matchLabels: {app: app-6}}
  template:
    metadata: {labels: {app: app-6}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "class-that-does-not-exist"
        resources:
          requests: {storage: 1Gi}
EOF

# [app-7] Init Container CrashLoopBackOff
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-7
  namespace: qa
spec:
  initContainers:
    - name: init-check
      image: busybox:1.36
      command: ["sh", "-c", "echo 'checking prerequisite...'; exit 1"]
  containers:
    - name: app
      image: nginx:1.25
EOF

# [app-8] Volume Mount Error - Missing Secret key
kubectl create secret generic secret-8 -n qa \
  --from-literal=tls.crt="not-a-real-cert" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-8
  namespace: qa
spec:
  replicas: 1
  selector: {matchLabels: {app: app-8}}
  template:
    metadata: {labels: {app: app-8}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - name: tls
              mountPath: /etc/nginx/tls
              readOnly: true
      volumes:
        - name: tls
          secret:
            secretName: secret-8
            items:
              - key: tls.key
                path: tls.key
EOF

# [app-9] Volume Mount Error - ConfigMap subPath mismatch
kubectl create configmap config-9 -n qa \
  --from-literal=app.conf="listen 80;" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-9
  namespace: qa
spec:
  replicas: 1
  selector: {matchLabels: {app: app-9}}
  template:
    metadata: {labels: {app: app-9}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          volumeMounts:
            - name: conf
              mountPath: /etc/app/app.conf
              subPath: app.conf.wrong
      volumes:
        - name: conf
          configMap:
            name: config-9
EOF

# [app-10] NetworkPolicy blocks traffic
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-10
  namespace: qa
spec:
  replicas: 1
  selector: {matchLabels: {app: app-10}}
  template:
    metadata: {labels: {app: app-10}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: app-10
  namespace: qa
spec:
  selector: {app: app-10}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: v1
kind: Pod
metadata:
  name: curl-debug
  namespace: qa
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
  name: netpol-1
  namespace: qa
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
EOF

echo -e "${GREEN}✓ QA namespace: 10 basic issues created${NC}"

# ============================================================
# ADVANCED NAMESPACE - ADVANCED ISSUES (app-11 to app-20)
# ============================================================
echo -e "\n${YELLOW}==> Seeding ADVANCED namespace with complex issues (app-11..app-20)...${NC}"

# [app-11] PVC Pending - No StorageClass exists
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

# [app-12] Multi-Attach Error - RWO with 2 replicas
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
  replicas: 2
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

# [app-13] Node Affinity mismatch
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
                    values: ["windows"]
      containers:
        - name: app
          image: nginx:1.25
EOF

# [app-14] Taint without toleration
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-14
  namespace: advanced
spec:
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  containers:
    - name: app
      image: nginx:1.25
EOF

# [app-15] DNS Failure
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
      - 192.0.2.100
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "nslookup kubernetes.default.svc.cluster.local || sleep 3600"]
EOF

# [app-16] Stuck Rollout
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
kubectl set image deployment/app-16 app=nginx:broken-tag-12345 -n advanced

# [app-17] StatefulSet PVC conflict
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

# Create conflicting PVC if not exists
if ! kubectl get pvc data-app-17-0 -n advanced &>/dev/null; then
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
    requests: {storage: 5Gi}
  storageClassName: standard
EOF
else
  echo "  - PVC data-app-17-0 already exists, skipping"
fi

# [app-18] HostPort conflict
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
              hostPort: 18080
EOF

# [app-19] Immutable ConfigMap
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
kubectl patch configmap app-19-config -n advanced --type merge -p '{"data":{"app.conf":"max_connections=200"}}' || echo "  - Expected failure: Immutable ConfigMap"

# [app-20] Service DNS mismatch
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
  name: database-svc
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

echo -e "${GREEN}✓ Advanced namespace: 10 complex issues created${NC}"

# ============================================================
# SUMMARY
# ============================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Lab Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Namespaces created:${NC}"
echo "  - qa:        10 basic issues (app-1 to app-10)"
echo "  - advanced:  10 advanced issues (app-11 to app-20)"
echo ""
echo -e "${YELLOW}Quick verification commands:${NC}"
echo "  kubectl get pods -n qa -o wide"
echo "  kubectl get pods -n advanced -o wide"
echo "  kubectl get pvc -n advanced"
echo ""
echo -e "${YELLOW}Start troubleshooting with:${NC}"
echo "  kubectl get pods -n qa"
echo "  kubectl get pods -n advanced"
echo "  kubectl describe pod <pod-name> -n <namespace>"
echo ""
echo -e "${YELLOW}Cleanup when done:${NC}"
echo "  kubectl delete namespace qa advanced"
