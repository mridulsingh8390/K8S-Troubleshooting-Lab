#!/usr/bin/env bash
# day10-helm-webhooks/01-create-issues.sh
# Namespace: day10 (+ a separate 'day10-stuck' namespace for app-5, plus
# cluster-scoped objects: a CRD and a ValidatingWebhookConfiguration).
#
# Theme: Helm release failures, a broken admission webhook, and CRDs
# without a controller — including a namespace deliberately stuck in
# Terminating. None of these are touched by earlier days.
#
# SAFETY NOTE on app-3: the webhook is scoped via namespaceSelector to
# ONLY namespaces labeled "webhook-demo=true" (just 'day10'), and its
# rule only intercepts Pod CREATE. It cannot affect any other namespace
# or any other day's resources.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day10"
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Building a minimal local Helm chart for app-1/app-2..."
CHART_DIR="/tmp/day10-chart"
rm -rf "${CHART_DIR}"
mkdir -p "${CHART_DIR}/templates"
cat > "${CHART_DIR}/Chart.yaml" <<'EOF'
apiVersion: v2
name: day10-chart
version: 0.1.0
EOF
cat > "${CHART_DIR}/values.yaml" <<'EOF'
image:
  repository: nginx
  tag: "1.25"
replicaCount: 1
EOF
cat > "${CHART_DIR}/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector: {matchLabels: {app: {{ .Release.Name }}}}
  template:
    metadata: {labels: {app: {{ .Release.Name }}}}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ required "image.tag must be set!" .Values.image.tag }}"
EOF

# [ANSWER KEY - app-1]: The override file sets "imageTag" instead of the
# chart's actual expected key "image.tag" — the chart's `required`
# guard catches the missing value immediately and helm install fails
# outright with a clear render error, before creating ANY Kubernetes
# objects. Fix: correct the override to set image.tag (nested under
# image:), not a flat imageTag key.
echo "==> [app-1] Attempting helm install with a bad values override (expected to fail)..."
cat > /tmp/day10-app1-values.yaml <<'EOF'
imageTag: "1.25"
EOF
helm install app-1 "${CHART_DIR}" -n "${NS}" -f /tmp/day10-app1-values.yaml \
  || echo "==> [app-1] helm install failed as expected — that's the bug. Fix the values file and retry."

# [ANSWER KEY - app-2]: First a working release is installed. Then an
# upgrade with --atomic and a bad image tag is attempted — it never
# becomes ready, so Helm automatically rolls back to the previous good
# revision once the timeout hits. The `helm upgrade` command reports
# failure, but by the time you look, the Deployment is silently back on
# the OLD image — nothing appears "currently broken", which is exactly
# what makes this confusing. Check `helm history app-2 -n day10` and
# `helm status app-2 -n day10` to see the rollback. Fix: identify the bad
# tag from the failed revision and re-upgrade with a valid one.
echo "==> [app-2] Installing a working release..."
helm install app-2 "${CHART_DIR}" -n "${NS}" --wait --timeout 60s

echo "==> [app-2] Upgrading with a bad tag under --atomic (expected to auto-rollback)..."
helm upgrade app-2 "${CHART_DIR}" -n "${NS}" \
  --set image.tag=this-tag-does-not-exist \
  --atomic --timeout 30s \
  || echo "==> [app-2] Upgrade rolled back as expected — check 'helm history app-2 -n day10'."

# [ANSWER KEY - app-3]: A ValidatingWebhookConfiguration with
# failurePolicy: Fail points at a Service that was never created. Every
# NEW pod creation in namespace day10 (only — see the SAFETY NOTE at the
# top of this file) now fails with "failed calling webhook" even though
# the Deployment/Pod spec itself is completely fine. Fix: either create
# the missing Service (backed by a real webhook server — out of scope
# here) or delete/fix the ValidatingWebhookConfiguration if it's not
# actually needed.
echo "==> [app-3] Labeling namespace and installing a broken ValidatingWebhookConfiguration..."
kubectl label namespace "${NS}" webhook-demo=true --overwrite

cat <<EOF | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: app-3-webhook
webhooks:
  - name: app-3.example.com
    admissionReviewVersions: ["v1"]
    sideEffects: None
    failurePolicy: Fail
    namespaceSelector:
      matchLabels:
        webhook-demo: "true"
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
    clientConfig:
      service:
        name: webhook-svc-that-does-not-exist
        namespace: ${NS}
        path: /validate
      caBundle: ""
EOF

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
EOF

# [ANSWER KEY - app-4]: A CRD is installed and a custom resource created
# from it, but no controller/operator is watching this CRD — so the
# Widget just sits there with no status, forever. There's no error
# anywhere; `kubectl get widget` shows it exists, `kubectl describe`
# shows an empty status. This is the "silent" failure mode: nothing is
# reconciling it because nothing was ever installed to do so.
echo "==> [app-4] Installing a CRD with no controller behind it..."
cat <<'EOF' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  group: example.com
  names: {kind: Widget, plural: widgets, singular: widget}
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec: {type: object, x-kubernetes-preserve-unknown-fields: true}
            status: {type: object, x-kubernetes-preserve-unknown-fields: true}
EOF

echo "==> [app-4] Waiting for the CRD to become Established..."
kubectl wait --for=condition=Established crd/widgets.example.com --timeout=30s

cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: Widget
metadata:
  name: app-4
  namespace: ${NS}
spec:
  size: large
EOF

# [ANSWER KEY - app-5]: A separate namespace is deleted while it still
# contains a Widget with a finalizer that no controller will ever remove
# (simulating an operator that was uninstalled without cleaning up after
# itself). The namespace enters Terminating and will stay there
# indefinitely — `kubectl get namespace day10-stuck` never finishes.
# Fix: find what's blocking it (`kubectl get widget -n day10-stuck -o
# yaml` — look at metadata.finalizers), then manually clear the
# finalizer so Kubernetes can finish garbage-collecting the namespace:
#   kubectl patch widget <name> -n day10-stuck --type=merge \
#     -p '{"metadata":{"finalizers":[]}}'
# Use this pattern with real caution in production — only after
# confirming the owning controller is genuinely gone and won't come back
# to finish cleanup itself.
echo "==> [app-5] Creating a namespace with a stuck finalizer, then deleting it..."
kubectl create namespace day10-stuck --dry-run=client -o yaml | kubectl apply -f -
cat <<'EOF' | kubectl apply -f -
apiVersion: example.com/v1
kind: Widget
metadata:
  name: stuck-widget
  namespace: day10-stuck
  finalizers:
    - example.com/cleanup-that-never-happens
spec:
  size: large
EOF
kubectl delete namespace day10-stuck --wait=false

echo ""
echo "==> Done. Day 10 issues created."
echo "==> kubectl get pods,deploy -n ${NS} ; helm list -n ${NS}"
echo "==> kubectl get validatingwebhookconfiguration app-3-webhook"
echo "==> kubectl get widget -A"
echo "==> kubectl get namespace day10-stuck"
