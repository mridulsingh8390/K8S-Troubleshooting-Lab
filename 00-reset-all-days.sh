#!/usr/bin/env bash
# 00-reset-all-days.sh
# Wipes all day1..day5 practice namespaces plus the day4 ClusterRoleBinding.
# Run from the k8s-practice/ root.
set -euo pipefail

kubectl delete clusterrolebinding overprivileged-binding-day4 --ignore-not-found

for ns in day1 day2 day3 day4 day5; do
  echo "==> Deleting namespace '${ns}' (if it exists)..."
  kubectl delete namespace "${ns}" --ignore-not-found --wait=true
done

echo "==> Done. All day1..day5 namespaces removed."
