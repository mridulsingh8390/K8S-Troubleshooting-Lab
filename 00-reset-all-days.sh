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
#
# This does NOT touch the kind cluster itself - only the namespaces/
# cluster-scoped objects created by the *-create-issues.sh scripts. Use
# each folder's own 03-delete-cluster.sh (or Day-0 has no cluster-delete
# script of its own - use any day's) if you want to tear down the cluster
# entirely.
#
# Run from the repo root: ./00-reset-all-days.sh

set -euo pipefail

echo "==> [Day-0] Deleting namespaces 'dev' and 'test'..."
kubectl delete namespace dev  --ignore-not-found --wait=true
kubectl delete namespace test --ignore-not-found --wait=true

echo "==> [day4] Deleting cluster-scoped ClusterRoleBinding..."
kubectl delete clusterrolebinding overprivileged-binding-day4 --ignore-not-found

for ns in day1 day2 day3 day4 day5; do
  echo "==> Deleting namespace '${ns}' (if it exists)..."
  kubectl delete namespace "${ns}" --ignore-not-found --wait=true
done

echo ""
echo "==> Done. dev, test, and day1..day5 namespaces removed."
echo "==> Re-seed any day by running its 01-create-issues.sh (or 02-create-issues-round1.sh"
echo "    / 03-create-issues-round2.sh for Day-0)."
