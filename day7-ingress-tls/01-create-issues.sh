#!/usr/bin/env bash
# day7-ingress-tls/01-create-issues.sh
# Namespace: day7
# Theme: Ingress routing and TLS. Requires ingress-nginx, which
# 00-setup-cluster.sh installs for you.
#
# This kind cluster has no host port-mapping for 80/443, so test from
# INSIDE the cluster using curl-debug and the Host header, not from your
# browser:
#   kubectl exec -it curl-debug -n day7 -- \
#     curl -sv -H "Host: app-1.example.com" http://ingress-nginx-controller.ingress-nginx.svc.cluster.local
#
# All resources are named app-1..app-5. Comments are the answer key —
# avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day7"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Shared debug pod for testing Ingress from inside the cluster..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-debug
  namespace: ${NS}
  labels: {app: curl-debug}
spec:
  containers:
    - name: curl
      image: curlimages/curl:8.8.0
      command: ["sleep", "3600"]
EOF

# [ANSWER KEY - app-1]: The Ingress backend references Service port 8080,
# but the Service itself only exposes port 80 — traffic reaches
# ingress-nginx, which reaches the Service, but the Service has no such
# port, resulting in a 503.
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
      containers:
        - name: app
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: app-1
  namespace: ${NS}
spec:
  selector: {app: app-1}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-1
  namespace: ${NS}
spec:
  ingressClassName: nginx
  rules:
    - host: app-1.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-1
                port: {number: 8080}
EOF

# [ANSWER KEY - app-2]: ingressClassName is missing entirely, so
# ingress-nginx never adopts this Ingress — it's created as an object but
# produces no route at all. Curling app-2's host just falls through to
# ingress-nginx's default backend (404), even though the Deployment and
# Service are both perfectly healthy.
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
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: app-2
  namespace: ${NS}
spec:
  selector: {app: app-2}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-2
  namespace: ${NS}
spec:
  rules:
    - host: app-2.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-2
                port: {number: 80}
EOF

# [ANSWER KEY - app-3]: pathType is "Exact" on "/", which only matches the
# literal path "/" — requests to "/anything-else" get a 404 even though a
# Prefix match would have caught them. A very common Ingress gotcha.
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
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: app-3
  namespace: ${NS}
spec:
  selector: {app: app-3}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-3
  namespace: ${NS}
spec:
  ingressClassName: nginx
  rules:
    - host: app-3.example.com
      http:
        paths:
          - path: /
            pathType: Exact
            backend:
              service:
                name: app-3
                port: {number: 80}
EOF

# [ANSWER KEY - app-4]: The Ingress's tls.secretName references a Secret
# that was never created — ingress-nginx falls back to its default
# self-signed cert for this host instead of a real one, and the Ingress
# controller logs will show it can't find the referenced Secret.
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
      containers:
        - name: app
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: app-4
  namespace: ${NS}
spec:
  selector: {app: app-4}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-4
  namespace: ${NS}
spec:
  ingressClassName: nginx
  tls:
    - hosts: ["app-4.example.com"]
      secretName: tls-secret-that-does-not-exist
  rules:
    - host: app-4.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-4
                port: {number: 80}
EOF

# [ANSWER KEY - app-5]: TWO Ingress objects both claim the exact same
# host+path, pointing at two different Services. Only one wins (behavior
# depends on ingress-nginx's internal ordering, which is intentionally
# not something you should rely on) — curling app-5.example.com gets an
# unpredictable/"wrong" backend, and the fix is removing the duplicate
# route or giving them distinct hosts/paths.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-5a
  namespace: ${NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: app-5a}}
  template:
    metadata: {labels: {app: app-5a}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: app-5a
  namespace: ${NS}
spec:
  selector: {app: app-5a}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-5a
  namespace: ${NS}
spec:
  ingressClassName: nginx
  rules:
    - host: app-5.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: {name: app-5a, port: {number: 80}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-5b
  namespace: ${NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: app-5b}}
  template:
    metadata: {labels: {app: app-5b}}
    spec:
      containers:
        - name: app
          image: httpd:2.4
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata:
  name: app-5b
  namespace: ${NS}
spec:
  selector: {app: app-5b}
  ports: [{port: 80, targetPort: 80}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-5b
  namespace: ${NS}
spec:
  ingressClassName: nginx
  rules:
    - host: app-5.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: {name: app-5b, port: {number: 80}}
EOF

echo ""
echo "==> Done. Day 7 issues created in namespace '${NS}'."
echo "==> Test each with, e.g.:"
echo "    kubectl exec -it curl-debug -n ${NS} -- curl -sv -H 'Host: app-1.example.com' http://ingress-nginx-controller.ingress-nginx.svc.cluster.local"
echo "==> kubectl get ingress -n ${NS}"
