#!/usr/bin/env bash
# 02-create-issues-round1.sh
# Seeds 'dev' and 'test' namespaces with intentionally broken Deployments.
# All resources are named generically (app-1, app-2, ...) so the issue type
# cannot be guessed from `kubectl get deploy` alone.
#
# Solve them yourself with kubectl describe/logs/get events. The comments
# in this script are the answer key - avoid reading them until you're stuck.
#
# Usage: chmod +x 02-create-issues-round1.sh && ./02-create-issues-round1.sh

set -euo pipefail

echo "==> Creating namespaces..."
kubectl create namespace dev  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace test --dry-run=client -o yaml | kubectl apply -f -

# ============================================================
# DEV NAMESPACE — 5 issues (app-1 .. app-5)
# ============================================================

# [ANSWER KEY - app-1]: CreateContainerConfigError - env references secret
# key "username" but the Secret only has "db_username".
kubectl create secret generic secret-1 -n dev \
  --from-literal=db_username=admin \
  --from-literal=db_password=supersecret \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-1
  namespace: dev
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
  namespace: dev
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
  namespace: dev
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
  namespace: dev
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
  namespace: dev
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
# TEST NAMESPACE — 5 issues (app-1 .. app-5, different variants)
# ============================================================

# [ANSWER KEY - app-1]: CreateContainerConfigError - envFrom references a
# ConfigMap that was never created.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-1
  namespace: test
spec:
  replicas: 1
  selector: {matchLabels: {app: app-1}}
  template:
    metadata: {labels: {app: app-1}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          envFrom:
            - configMapRef:
                name: config-1-does-not-exist
EOF

# [ANSWER KEY - app-2]: ImagePullBackOff - registry hostname doesn't resolve.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-2
  namespace: test
spec:
  replicas: 1
  selector: {matchLabels: {app: app-2}}
  template:
    metadata: {labels: {app: app-2}}
    spec:
      containers:
        - name: app
          image: this-registry-does-not-exist.example.com/app:1.0
EOF

# [ANSWER KEY - app-3]: OOMKilled / CrashLoopBackOff - memory limit too low
# for what the process allocates.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-3
  namespace: test
spec:
  replicas: 1
  selector: {matchLabels: {app: app-3}}
  template:
    metadata: {labels: {app: app-3}}
    spec:
      containers:
        - name: app
          image: polinux/stress
          command: ["stress"]
          args: ["--vm", "1", "--vm-bytes", "300M", "--vm-hang", "0"]
          resources:
            limits:
              memory: "50Mi"
EOF

# [ANSWER KEY - app-4]: Pending - nodeSelector matches no node in the cluster.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-4
  namespace: test
spec:
  replicas: 1
  selector: {matchLabels: {app: app-4}}
  template:
    metadata: {labels: {app: app-4}}
    spec:
      nodeSelector:
        disktype: ssd-that-does-not-exist
      containers:
        - name: app
          image: nginx:1.25
EOF

# [ANSWER KEY - app-5]: Pods healthy, but the Service selector doesn't match
# the pod labels, so it has zero endpoints.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-5
  namespace: test
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
---
apiVersion: v1
kind: Service
metadata:
  name: app-5
  namespace: test
spec:
  selector:
    app: app-5-wrong-label
  ports:
    - port: 80
      targetPort: 80
EOF

echo ""
echo "==> Done. 10 broken Deployments created (app-1..app-5 in both dev and test)."
echo "==> Start troubleshooting with:"
echo "    kubectl get pods -n dev"
echo "    kubectl get pods -n test"
echo "    kubectl describe pod <pod> -n <namespace>"