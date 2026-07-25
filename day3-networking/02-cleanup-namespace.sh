#!/usr/bin/env bash
# day3-networking/02-cleanup.sh
set -euo pipefail
kubectl delete namespace day3 --ignore-not-found --wait=true
echo "==> day3 namespace removed. Re-seed with ./01-create-issues.sh"
