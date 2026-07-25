#!/usr/bin/env bash
# 04-cleanup-round1.sh
# Deletes only the Round 1 resources (app-1..app-5 and their supporting
# Secret/Service) from 'dev' and 'test', so you can re-run
# 02-create-issues-round1.sh from scratch without touching any Round 2
# (app-6..app-10) resources that may also be present.
#
# Usage: chmod +x 04-cleanup-round1.sh && ./04-cleanup-round1.sh

set -euo pipefail

for ns in dev test; do
  echo "==> [${ns}] Deleting Round 1 Deployments (app-1..app-5)..."
  kubectl delete deployment app-1 app-2 app-3 app-4 app-5 \
    -n "${ns}" --ignore-not-found

  echo "==> [${ns}] Deleting Round 1 Service (app-5, test namespace only)..."
  kubectl delete service app-5 -n "${ns}" --ignore-not-found

  echo "==> [${ns}] Deleting Round 1 Secret (secret-1, dev namespace only)..."
  kubectl delete secret secret-1 -n "${ns}" --ignore-not-found
done

echo ""
echo "==> Done. Round 1 resources removed."
echo "==> Verify with:"
echo "    kubectl get deploy,svc,secret -n dev"
echo "    kubectl get deploy,svc,secret -n test"
echo "==> Re-seed with: ./02-create-issues-round1.sh"
