#!/usr/bin/env bash
# day7-ingress-tls/02-cleanup-namespace.sh
# Deletes the 'day7' namespace. Leaves ingress-nginx itself installed
# (it lives in the 'ingress-nginx' namespace) so you can re-run
# 01-create-issues.sh without reinstalling the controller.
set -euo pipefail
kubectl delete namespace day7 --ignore-not-found --wait=true
echo "==> day7 namespace removed (ingress-nginx controller left in place)."
echo "==> Re-seed with ./01-create-issues.sh"
