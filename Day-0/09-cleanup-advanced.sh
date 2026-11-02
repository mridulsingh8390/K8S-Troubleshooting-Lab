#!/usr/bin/env bash
set -euo pipefail
kubectl delete namespace advanced --ignore-not-found --wait=true
kubectl create namespace advanced
echo "==> Advanced namespace recreated empty."