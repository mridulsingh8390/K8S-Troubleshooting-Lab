#!/usr/bin/env bash
# day1-workloads/01-create-issues.sh
# Namespace: day1
# Theme: core Deployment/workload failures — new variants, distinct from the
# earlier dev/test round1+round2 exercises.
#
# All resources are named app-1..app-5. Comments are the answer key —
# avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day1"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: Pod never gets created — Deployment references a
# ServiceAccount that doesn't exist. Check `kubectl describe rs` / events on
# the ReplicaSet, not the pod (there is no pod).
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
      serviceAccountName: sa-that-does-not-exist
      containers:
        - name: app
          image: nginx:1.25
EOF

# [ANSWER KEY - app-2]: CrashLoopBackOff — the command binary does not exist
# in the image ("exec: no such file or directory").
cat <<EOF | kubectl apply -f -
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
          image: busybox:1.36
          command: ["/this-binary-does-not-exist"]
EOF

# [ANSWER KEY - app-3]: ImagePullBackOff — image is referenced by a digest
# that does not exist in the registry.
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
          image: nginx@sha256:0000000000000000000000000000000000000000000000000000000000aa
EOF

# [ANSWER KEY - app-4]: Pending — podAntiAffinity requires every replica on
# a distinct node, but this cluster only has 2 schedulable worker nodes
# (control-plane is tainted) for 3 requested replicas.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-4
  namespace: ${NS}
spec:
  replicas: 3
  selector: {matchLabels: {app: app-4}}
  template:
    metadata: {labels: {app: app-4}}
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels: {app: app-4}
              topologyKey: "kubernetes.io/hostname"
      containers:
        - name: app
          image: nginx:1.25
EOF

# [ANSWER KEY - app-5]: Restarts keep climbing (Running, but repeatedly
# killed) — livenessProbe is pointed at the wrong port, so the kubelet kills
# a perfectly healthy container over and over.
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
          image: nginx:1.25
          ports: [{containerPort: 80}]
          livenessProbe:
            httpGet: {path: /, port: 8081}
            initialDelaySeconds: 5
            periodSeconds: 5
EOF

echo ""
echo "==> Done. Day 1 issues created in namespace '${NS}' (app-1..app-5)."
echo "==> kubectl get deploy,rs,pods -n ${NS}"
