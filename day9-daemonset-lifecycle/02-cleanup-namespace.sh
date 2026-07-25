#!/usr/bin/env bash
# day9-daemonset-lifecycle/02-cleanup-namespace.sh
set -euo pipefail
kubectl delete namespace day9 --ignore-not-found --wait=true
echo "==> day9 namespace removed."
echo "==> If you ran a real (non --dry-run) drain against practice-worker for app-3,"
echo "    uncordon it: kubectl uncordon practice-worker"
echo "==> Re-seed with: ./01-create-issues.sh"
