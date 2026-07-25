#!/usr/bin/env bash
# day3-networking/01-create-issues.sh
# Namespace: day3
# Theme: networking & service discovery (NetworkPolicy, Service ports, DNS).
#
# All resources are named app-1..app-5. Comments are the answer key —
# avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day3"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Shared debug pod for connectivity testing..."
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

# [ANSWER KEY - app-1]: App listens on 80, but the NetworkPolicy only
# allows ingress on port 8080 — connectivity is refused despite a policy
# that looks like it should permit it.
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
kind: NetworkPolicy
metadata:
  name: netpol-app-1
  namespace: ${NS}
spec:
  podSelector: {matchLabels: {app: app-1}}
  policyTypes: ["Ingress"]
  ingress:
    - from: [{podSelector: {matchLabels: {app: curl-debug}}}]
      ports: [{protocol: TCP, port: 8080}]
EOF

# [ANSWER KEY - app-2]: Service has endpoints, but targetPort doesn't match
# the container's actual listening port (targetPort: 8080, nginx listens
# on 80) — connection refused even though endpoints exist.
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
  ports: [{port: 80, targetPort: 8080}]
EOF

# [ANSWER KEY - app-3]: dnsPolicy is set to "None" with no dnsConfig
# supplied, so the pod has no nameservers at all — DNS lookups fail
# entirely (curl by service name fails, curl by ClusterIP works).
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
      dnsPolicy: "None"
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
EOF

# [ANSWER KEY - app-4]: Service selector requires TWO labels
# (app=app-4 AND tier=backend), but the pod only carries one of them —
# a partial label match is still a non-match. Selectors are AND, not OR.
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
  selector: {app: app-4, tier: backend}
  ports: [{port: 80, targetPort: 80}]
EOF

# [ANSWER KEY - app-5]: A default-deny-all EGRESS policy blocks port 53,
# so pods behind it can't reach CoreDNS at all — every DNS lookup times
# out, breaking connectivity to anything referenced by name.
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
          image: curlimages/curl:8.8.0
          command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: netpol-app-5-egress
  namespace: ${NS}
spec:
  podSelector: {matchLabels: {app: app-5}}
  policyTypes: ["Egress"]
  egress: []
EOF

echo ""
echo "==> Done. Day 3 issues created in namespace '${NS}' (app-1..app-5)."
echo "==> Test connectivity from inside the namespace, e.g.:"
echo "    kubectl exec -it curl-debug -n ${NS} -- curl -v app-1:80"
echo "    kubectl exec -it deploy/app-5 -n ${NS} -- nslookup app-1"
