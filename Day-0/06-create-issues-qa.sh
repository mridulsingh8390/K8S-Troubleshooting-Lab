#!/usr/bin/env bash
# 06-create-issues-qa.sh
# Creates a dedicated QA namespace with the same Round 1 and Round 2
# troubleshooting scenarios used in the original dev namespace.
# WARNING: These workloads are intentionally broken for practice.
# Run this only in your disposable Kind practice cluster.
# Usage: chmod +x 06-create-issues-qa.sh && ./06-create-issues-qa.sh

set -euo pipefail

kubectl create namespace qa --dry-run=client -o yaml | kubectl apply -f -

echo "==> Seeding QA with Round 1 issues (app-1..app-5)..."
# ============================================================
# DEV NAMESPACE — 5 issues (app-1 .. app-5)
# ============================================================

# [ANSWER KEY - app-1]: CreateContainerConfigError - env references secret
# key "username" but the Secret only has "db_username".
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

# [ANSWER KEY - app-2]: ImagePullBackOff - image tag does not exist.
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

# [ANSWER KEY - app-3]: CrashLoopBackOff - container command exits 1 immediately.
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

# [ANSWER KEY - app-4]: Pending - resource requests exceed any node's capacity.
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

# [ANSWER KEY - app-5]: Running but 0/1 Ready - readiness probe path is wrong.
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

# ============================================================

echo "==> Seeding QA with Round 2 issues (app-6..app-10)..."
# ============================================================
# DEV NAMESPACE — 5 issues (app-6 .. app-10)
# ============================================================

# [ANSWER KEY - app-6]: StatefulSet PVCs stuck Pending - storageClassName
# doesn't exist.
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

# [ANSWER KEY - app-7]: Stuck at Init:CrashLoopBackOff - init container
# always exits 1.
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

# [ANSWER KEY - app-8]: Volume mount error - Secret is missing the "tls.key"
# data key that the pod spec references.
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

# [ANSWER KEY - app-9]: Volume mount error - subPath references a ConfigMap
# key that doesn't exist ("app.conf.wrong" vs actual key "app.conf").
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

# [ANSWER KEY - app-10]: Working app, but a default-deny NetworkPolicy
# blocks all ingress - curl-debug can't reach it until an allow rule is added.
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

# ============================================================

echo "==> QA issue lab created. Inspect with: kubectl get pods,deploy,sts,pvc,svc -n qa"
