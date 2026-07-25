#!/usr/bin/env bash
# 00-reset-all-days.sh
# Wipes ALL practice namespaces across the entire lab in one shot:
#   - Day-0:        dev, test
#   - day1-workloads:      day1
#   - day2-storage:        day2
#   - day3-networking:     day3
#   - day4-security-rbac:  day4 (+ its ClusterRoleBinding, which is
#                           cluster-scoped and not removed by deleting
#                           the namespace)
#   - day5-jobs-quotas:    day5
#   - day6-control-plane:  day6 (+ reverts node/control-plane changes —
#                           see day6's own 02-cleanup-namespace.sh, which
#                           this script delegates to since a plain
#                           `kubectl delete namespace` isn't enough there)
#   - day7-ingress-tls:    day7 (ingress-nginx itself is left installed)
#
# This does NOT touch the kind cluster itself - only the namespaces/
# cluster-scoped/node-level objects created by the *-create-issues.sh
# scripts. Use any day's 03-delete-cluster.sh if you want to tear down
# the cluster entirely.
#
# Run from the repo root: ./00-reset-all-days.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [Day-0] Deleting namespaces 'dev' and 'test'..."
kubectl delete namespace dev  --ignore-not-found --wait=true
kubectl delete namespace test --ignore-not-found --wait=true

echo "==> [day4] Deleting cluster-scoped ClusterRoleBinding..."
kubectl delete clusterrolebinding overprivileged-binding-day4 --ignore-not-found

for ns in day1 day2 day3 day4 day5 day7; do
  echo "==> Deleting namespace '${ns}' (if it exists)..."
  kubectl delete namespace "${ns}" --ignore-not-found --wait=true
done

echo "==> [day6] Delegating to day6's own cleanup script (reverts kubelet/static pod changes too)..."
if [ -f "${SCRIPT_DIR}/day6-control-plane/02-cleanup-namespace.sh" ]; then
  bash "${SCRIPT_DIR}/day6-control-plane/02-cleanup-namespace.sh" || \
    echo "==> WARNING: day6 cleanup hit an error — check node state manually (see day6-control-plane/README section)."
else
  echo "==> WARNING: day6-control-plane/02-cleanup-namespace.sh not found — day6's node-level changes were NOT reverted."
fi

echo ""
echo "==> Done. dev, test, and day1..day7 namespaces removed (day6 node/control-plane state reverted too)."
echo "==> Re-seed any day by running its 01-create-issues.sh (or 02-create-issues-round1.sh"
echo "    / 03-create-issues-round2.sh for Day-0)."
