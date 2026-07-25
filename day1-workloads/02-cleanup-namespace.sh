#!/usr/bin/env bash
# day1-workloads/02-cleanup.sh
# Deletes the entire 'day1' namespace so you can re-run 01-create-issues.sh
# from scratch.
set -euo pipefail
kubectl delete namespace day1 --ignore-not-found --wait=true
echo "==> day1 namespace removed. Re-seed with ./01-create-issues.sh"
