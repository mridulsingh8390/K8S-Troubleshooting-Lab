#!/usr/bin/env bash
# day2-storage/02-cleanup.sh
set -euo pipefail
kubectl delete namespace day2 --ignore-not-found --wait=true
echo "==> day2 namespace removed. Re-seed with ./01-create-issues.sh"
