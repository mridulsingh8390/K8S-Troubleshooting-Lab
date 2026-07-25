#!/usr/bin/env bash
# day5-jobs-quotas/02-cleanup.sh
set -euo pipefail
kubectl delete namespace day5 --ignore-not-found --wait=true
echo "==> day5 namespace removed. Re-seed with ./01-create-issues.sh"
