#!/usr/bin/env bash
# day5-jobs-quotas/01-create-issues.sh
# Namespace: day5
# Theme: Jobs/CronJobs, ResourceQuota, LimitRange, HorizontalPodAutoscaler.
#
# All resources are named app-1..app-5. Comments are the answer key —
# avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day5"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: Job's container always exits 1 — after
# backoffLimit retries, the Job is marked Failed.
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: app-1
  namespace: ${NS}
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "echo 'running job'; exit 1"]
EOF

# [ANSWER KEY - app-2]: Invalid cron schedule syntax
# ("* * * * 8" — day-of-week field only goes 0-6) — the CronJob object
# will either be rejected at apply time or never actually trigger,
# depending on cluster version. Fix the schedule string.
cat <<EOF | kubectl apply -f - || echo "==> [app-2] apply failed as expected — that's the bug, fix the schedule field."
apiVersion: batch/v1
kind: CronJob
metadata:
  name: app-2
  namespace: ${NS}
spec:
  schedule: "* * * * 8"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: app
              image: busybox:1.36
              command: ["echo", "hello from cronjob"]
EOF

# [ANSWER KEY - app-3]: ResourceQuota in this namespace caps total pods at
# 1, and a placeholder pod already consumes that slot — a second
# Deployment's ReplicaSet can never create its pod ("exceeded quota").
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata: {name: quota-day5, namespace: ${NS}}
spec:
  hard:
    pods: "1"
---
apiVersion: v1
kind: Pod
metadata: {name: placeholder, namespace: ${NS}, labels: {app: placeholder}}
spec:
  containers:
    - name: app
      image: nginx:1.25
---
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
EOF

# [ANSWER KEY - app-4]: A namespace-wide LimitRange sets a default memory
# limit of 20Mi. This Deployment doesn't specify its own memory limit, so
# it inherits 20Mi from the LimitRange and gets OOMKilled under normal load.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: {name: limits-day5, namespace: ${NS}}
spec:
  limits:
    - type: Container
      default: {memory: "20Mi"}
      defaultRequest: {memory: "10Mi"}
---
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
          image: polinux/stress
          command: ["stress"]
          args: ["--vm", "1", "--vm-bytes", "80M", "--vm-hang", "0"]
EOF

# [ANSWER KEY - app-5]: HPA's scaleTargetRef points at a Deployment name
# that was never created ("app-5-workload" instead of "app-5") — describe
# the HPA to see "FailedGetScale" / invalid target reference.
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
          resources:
            requests: {cpu: "100m"}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: app-5, namespace: ${NS}}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-5-workload
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: {type: Utilization, averageUtilization: 50}
EOF

echo ""
echo "==> Done. Day 5 issues created in namespace '${NS}' (app-1..app-5)."
echo "==> kubectl get job,cronjob,deploy,hpa,pods -n ${NS}"
echo "==> kubectl describe hpa app-5 -n ${NS}"
