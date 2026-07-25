#!/usr/bin/env bash
# 03-create-issues-round2.sh
# Round 2: StatefulSet, Secret, ConfigMap, init-container, sidecar, and
# NetworkPolicy issues layered on top of the dev/test namespaces from
# Round 1. Run 02-create-issues-round1.sh first (or at least make sure
# 'dev' and 'test' namespaces exist).
#
# All resources are named generically (app-6 .. app-10, continuing the
# numbering from round 1) so the issue type can't be guessed from
# `kubectl get sts,deploy,pod` alone.
#
# Solve them yourself first - the comments in this script are the answer key.
#
# Usage: chmod +x 03-create-issues-round2.sh && ./03-create-issues-round2.sh

set -euo pipefail

kubectl create namespace dev  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace test --dry-run=client -o yaml | kubectl apply -f -

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
  namespace: dev
spec:
  clusterIP: None
  selector: {app: app-6}
  ports: [{port: 80}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: app-6
  namespace: dev
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
  namespace: dev
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
kubectl create secret generic secret-8 -n dev \
  --from-literal=tls.crt="not-a-real-cert" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-8
  namespace: dev
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
kubectl create configmap config-9 -n dev \
  --from-literal=app.conf="listen 80;" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-9
  namespace: dev
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
  namespace: dev
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
  namespace: dev
spec:
  selector: {app: app-10}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: v1
kind: Pod
metadata:
  name: curl-debug
  namespace: dev
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
  namespace: dev
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
EOF

# ============================================================
# TEST NAMESPACE — 5 issues (app-6 .. app-10)
# ============================================================

# [ANSWER KEY - app-6]: StatefulSet references a headless Service
# ("app-6-headless-missing") that was never created - peer DNS won't resolve.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: app-6
  namespace: test
spec:
  serviceName: app-6-headless-missing
  replicas: 2
  selector: {matchLabels: {app: app-6}}
  template:
    metadata: {labels: {app: app-6}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
EOF

# [ANSWER KEY - app-7]: Multi-container pod - main container is fine, the
# second container crashes, so READY stays at 1/2.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-7
  namespace: test
spec:
  containers:
    - name: app
      image: nginx:1.25
    - name: sidecar
      image: busybox:1.36
      command: ["sh", "-c", "echo 'sidecar failing'; exit 1"]
EOF

# [ANSWER KEY - app-8]: FailedMount - Secret volume references a key
# ("api_token") that was never created in the Secret (actual key is "api_key").
kubectl create secret generic secret-8 -n test \
  --from-literal=api_key="abc123" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-8
  namespace: test
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
            - name: creds
              mountPath: /etc/secrets
      volumes:
        - name: creds
          secret:
            secretName: secret-8
            items:
              - key: api_token
                path: api_token
EOF

# [ANSWER KEY - app-9]: PVC stuck Pending - requests ReadWriteMany, which the
# default StorageClass in this cluster doesn't support.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-9
  namespace: test
spec:
  accessModes: ["ReadWriteMany"]
  resources:
    requests: {storage: 1Gi}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-9
  namespace: test
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
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: pvc-9
EOF

# [ANSWER KEY - app-10]: ConfigMap has an invalid key name (starts with a
# digit), which fails when consumed via envFrom.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: config-10
  namespace: test
data:
  "1invalid-key": "value"
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-10
  namespace: test
spec:
  replicas: 1
  selector: {matchLabels: {app: app-10}}
  template:
    metadata: {labels: {app: app-10}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          envFrom:
            - configMapRef:
                name: config-10
EOF

echo ""
echo "==> Done. Round 2 issues created (app-6..app-10 in both dev and test)."
echo "==> Start troubleshooting with:"
echo "    kubectl get pods,sts,pvc -n dev"
echo "    kubectl get pods,sts,pvc -n test"
echo "    kubectl describe pod/sts/pvc <name> -n <namespace>"