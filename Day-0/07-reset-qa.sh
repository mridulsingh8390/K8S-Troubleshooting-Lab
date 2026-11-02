#!/usr/bin/env bash
# 07-reset-qa.sh
# WARNING: Deletes the entire qa namespace and every resource inside it.
# Use only for the disposable troubleshooting lab.
set -euo pipefail

kubectl delete namespace qa --ignore-not-found --wait=true
kubectl create namespace qa
echo "==> QA namespace recreated and empty."
echo "==> Re-seed the troubleshooting scenarios with: ./06-create-issues-qa.sh"
