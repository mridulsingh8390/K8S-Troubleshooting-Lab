#!/usr/bin/env bash
# day9-daemonset-lifecycle/01-create-issues.sh
# Namespace: day9
# Theme: DaemonSets, PodDisruptionBudgets, and graceful-shutdown/probe
# timing — none of these are touched by earlier days.
#
# All resources are named app-1..app-5. Comments are the answer key —
# avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day9"
WORKER_NODE="practice-worker"
WORKER2_NODE="practice-worker2"

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: "DaemonSets run on every node" is only true if
# nothing in the spec narrows that down — this one has a nodeSelector
# that only matches practice-worker, not practice-worker2. It looks like
# a DaemonSet that "should" have a pod on every node, but
# `kubectl get daemonset` will show DESIRED/CURRENT less than the total
# node count, and there's no error anywhere — it's working exactly as
# configured, just not as assumed.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: app-1
  namespace: ${NS}
spec:
  selector: {matchLabels: {app: app-1}}
  template:
    metadata: {labels: {app: app-1}}
    spec:
      nodeSelector:
        kubernetes.io/hostname: ${WORKER_NODE}
      containers:
        - name: app
          image: nginx:1.25
EOF

# [ANSWER KEY - app-2]: A Pod already holds hostPort 9100 on
# ${WORKER2_NODE}. This DaemonSet also wants hostPort 9100 on every node
# — it schedules fine everywhere EXCEPT ${WORKER2_NODE}, where it's stuck
# Pending because the port is already claimed by another pod on that
# specific node (a real node-exporter-style port collision).
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: port-holder
  namespace: ${NS}
spec:
  nodeSelector:
    kubernetes.io/hostname: ${WORKER2_NODE}
  containers:
    - name: holder
      image: nginx:1.25
      ports: [{containerPort: 9100, hostPort: 9100}]
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: app-2
  namespace: ${NS}
spec:
  selector: {matchLabels: {app: app-2}}
  template:
    metadata: {labels: {app: app-2}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
          ports: [{containerPort: 9100, hostPort: 9100}]
EOF

# [ANSWER KEY - app-3]: A PodDisruptionBudget requires ALL 3 replicas to
# stay available at all times (minAvailable: 3 for 3 replicas leaves zero
# room for voluntary disruption). Draining ${WORKER_NODE} will hang/fail
# on evicting this app's pod if any of its replicas land there — the
# drain command itself will report why. Fix: lower minAvailable (or raise
# maxUnavailable) to something that actually allows at least one pod to
# be evicted at a time.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-3
  namespace: ${NS}
spec:
  replicas: 3
  selector: {matchLabels: {app: app-3}}
  template:
    metadata: {labels: {app: app-3}}
    spec:
      containers:
        - name: app
          image: nginx:1.25
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-3
  namespace: ${NS}
spec:
  minAvailable: 3
  selector: {matchLabels: {app: app-3}}
EOF

# [ANSWER KEY - app-4]: preStop sleeps for 30s to "clean up", but
# terminationGracePeriodSeconds is only 5s — the kubelet sends SIGKILL
# once the grace period expires regardless of whether preStop finished,
# so cleanup gets cut off mid-way every time this pod terminates. Fix:
# raise terminationGracePeriodSeconds to comfortably exceed the preStop
# duration (or shorten what preStop actually does).
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
      terminationGracePeriodSeconds: 5
      containers:
        - name: app
          image: nginx:1.25
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "echo 'cleaning up...'; sleep 30"]
EOF

# [ANSWER KEY - app-5]: The app takes ~20s to actually become ready, but
# startupProbe only allows failureThreshold(3) * periodSeconds(3) = 9s
# before giving up — the kubelet kills the container as "failed to
# start" before it ever gets the chance to finish starting. This looks
# identical to CrashLoopBackOff from a bad app, but the app itself is
# fine; the startup budget is just too small. Fix: raise failureThreshold
# and/or periodSeconds so the total budget comfortably exceeds real
# startup time.
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
          command: ["sh", "-c", "sleep 20; echo ready > /tmp/ready; sleep infinity"]
          startupProbe:
            exec:
              command: ["cat", "/tmp/ready"]
            periodSeconds: 3
            failureThreshold: 3
EOF

echo ""
echo "==> Done. Day 9 issues created in namespace '${NS}' (app-1..app-5)."
echo "==> kubectl get ds,deploy,pdb,pods -n ${NS} -o wide"
echo "==> For app-3, try: kubectl drain ${WORKER_NODE} --ignore-daemonsets --dry-run=server"
