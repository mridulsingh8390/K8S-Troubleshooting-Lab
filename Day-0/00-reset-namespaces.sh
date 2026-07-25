#!/usr/bin/env bash
# 00-reset-namespaces.sh
# Wipes and recreates 'dev' and 'test' namespaces so you can re-run
# Round 1 or Round 2 from a clean slate.
#
# Usage: chmod +x 00-reset-namespaces.sh && ./00-reset-namespaces.sh

set -euo pipefail

for ns in dev test; do
  echo "==> Deleting namespace '${ns}' (if it exists)..."
  kubectl delete namespace "${ns}" --ignore-not-found --wait=true
  echo "==> Recreating namespace '${ns}'..."
  kubectl create namespace "${ns}"
done

echo "==> Done. dev/test are now empty."
