#!/usr/bin/env bash
# day4-security-rbac/01-create-issues.sh
# Namespace: day4
# Theme: RBAC and Pod Security (CKS-style). Some of these aren't "crashing
# pods" — they're misconfigurations you have to find by auditing RBAC
# objects and admission behavior, closer to real security review work.
#
# All resources are named app-1..app-5. Comments are the answer key —
# avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day4"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: The pod's ServiceAccount only has RBAC permission to
# "get" pods, not "list" — the container loops calling `kubectl get pods`
# (a list operation) and logs a repeating 403 Forbidden.
kubectl create serviceaccount sa-1 -n "${NS}" --dry-run=client -o yaml | kubectl apply -f -
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: role-1, namespace: ${NS}}
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: rb-1, namespace: ${NS}}
subjects: [{kind: ServiceAccount, name: sa-1, namespace: ${NS}}]
roleRef: {kind: Role, name: role-1, apiGroup: rbac.authorization.k8s.io}
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
      serviceAccountName: sa-1
      containers:
        - name: app
          image: bitnami/kubectl:1.30
          command: ["sh", "-c", "while true; do kubectl get pods -n ${NS}; sleep 10; done"]
EOF

# [ANSWER KEY - app-2]: The RoleBinding subject name has a typo
# ("sa-2-typo" instead of "sa-2") — the Role and RoleBinding both exist and
# look correct at a glance, but they never actually apply to the pod's real
# ServiceAccount.
kubectl create serviceaccount sa-2 -n "${NS}" --dry-run=client -o yaml | kubectl apply -f -
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: role-2, namespace: ${NS}}
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: rb-2, namespace: ${NS}}
subjects: [{kind: ServiceAccount, name: sa-2-typo, namespace: ${NS}}]
roleRef: {kind: Role, name: role-2, apiGroup: rbac.authorization.k8s.io}
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
      serviceAccountName: sa-2
      containers:
        - name: app
          image: bitnami/kubectl:1.30
          command: ["sh", "-c", "while true; do kubectl get pods -n ${NS}; sleep 10; done"]
EOF

# [ANSWER KEY - app-3]: securityContext.runAsNonRoot is true, but the nginx
# image's default user is root — the container fails to start with a clear
# "container has runAsNonRoot and image will run as root" error in Events.
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
      securityContext:
        runAsNonRoot: true
      containers:
        - name: app
          image: nginx:1.25
EOF

# [ANSWER KEY - app-4]: The namespace enforces the "restricted" Pod
# Security Admission standard. This Deployment requests hostNetwork, which
# "restricted" forbids — the Deployment object itself is created
# successfully, but its ReplicaSet can never actually create a pod. Check
# `kubectl describe rs -l app=app-4` for the admission rejection message.
kubectl label namespace "${NS}" pod-security.kubernetes.io/enforce=restricted --overwrite
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-4
  namespace: ${NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: app-4}}
  template:
    metadata: {labels: {app: app-4}}
    spec:
      hostNetwork: true
      containers:
        - name: app
          image: nginx:1.25
EOF

# [ANSWER KEY - app-5]: AUDIT exercise, not a crash. A ClusterRoleBinding
# grants the namespace's default ServiceAccount full cluster-admin — far
# broader than anything in this namespace needs. Find it with:
#   kubectl get clusterrolebinding -o wide | grep day4
# and fix it by deleting the binding (or replacing it with a properly
# scoped Role/RoleBinding if the workload genuinely needs some permission).
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: overprivileged-binding-day4
subjects:
  - kind: ServiceAccount
    name: default
    namespace: ${NS}
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo ""
echo "==> Done. Day 4 issues created in namespace '${NS}' (app-1..app-5)."
echo "==> kubectl get deploy,rs,pods -n ${NS}"
echo "==> kubectl logs deploy/app-1 -n ${NS}   # and app-2, once running"
