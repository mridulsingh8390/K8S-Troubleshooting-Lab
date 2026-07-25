#!/usr/bin/env bash
# 05-cleanup-round2.sh
# Deletes only the Round 2 resources (app-6..app-10 and their supporting
# StatefulSets/Secrets/ConfigMaps/PVCs/NetworkPolicy/debug pod) from 'dev'
# and 'test', so you can re-run 03-create-issues-round2.sh from scratch
# without touching any Round 1 (app-1..app-5) resources that may also be
# present.
#
# Usage: chmod +x 05-cleanup-round2.sh && ./05-cleanup-round2.sh

set -euo pipefail

echo "==> [dev] Deleting Round 2 resources..."
kubectl delete statefulset app-6 -n dev --ignore-not-found
kubectl delete service app-6-headless app-10 -n dev --ignore-not-found
kubectl delete pod app-7 curl-debug -n dev --ignore-not-found
kubectl delete deployment app-8 app-9 app-10 -n dev --ignore-not-found
kubectl delete secret secret-8 -n dev --ignore-not-found
kubectl delete configmap config-9 -n dev --ignore-not-found
kubectl delete networkpolicy netpol-1 -n dev --ignore-not-found
# StatefulSet PVCs aren't removed by deleting the StatefulSet itself
kubectl delete pvc -n dev -l app=app-6 --ignore-not-found

echo "==> [test] Deleting Round 2 resources..."
kubectl delete statefulset app-6 -n test --ignore-not-found
kubectl delete pod app-7 -n test --ignore-not-found
kubectl delete deployment app-8 app-9 app-10 -n test --ignore-not-found
kubectl delete secret secret-8 -n test --ignore-not-found
kubectl delete configmap config-10 -n test --ignore-not-found
kubectl delete pvc pvc-9 -n test --ignore-not-found
kubectl delete pvc -n test -l app=app-6 --ignore-not-found

echo ""
echo "==> Done. Round 2 resources removed."
echo "==> Verify with:"
echo "    kubectl get deploy,sts,svc,secret,configmap,pvc,networkpolicy,pod -n dev"
echo "    kubectl get deploy,sts,svc,secret,configmap,pvc,pod -n test"
echo "==> Re-seed with: ./03-create-issues-round2.sh"
