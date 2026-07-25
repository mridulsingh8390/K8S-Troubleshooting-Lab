#!/usr/bin/env bash
# 01-setup-kind-cluster.sh
# Installs Docker, kubectl, and kind on Ubuntu, then creates a 3-node
# (1 control-plane + 2 workers) kind cluster for troubleshooting practice.
#
# Usage: chmod +x 01-setup-kind-cluster.sh && ./01-setup-kind-cluster.sh

set -euo pipefail

CLUSTER_NAME="practice"
KIND_VERSION="v0.32.0"
# kindest/node image pinned to Kubernetes v1.34.8 (matches kind v0.32.0 release)
NODE_IMAGE="kindest/node:v1.34.8@sha256:02722c2dedddcfc00febf5d27fbeb9b7b2c14294c82109ff4a85d89ac9ba3256"

echo "==> Checking prerequisites..."

# ---- Docker ----
if ! command -v docker &>/dev/null; then
  echo "==> Installing Docker..."
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "==> Docker installed. You may need to log out/in for group membership to take effect."
else
  echo "==> Docker already installed: $(docker --version)"
fi

# ---- kubectl ----
# Pinned to v1.34.x to match the cluster's Kubernetes version (kubectl
# supports +/-1 minor skew from the server, but matching avoids surprises).
KUBECTL_VERSION="v1.34.8"
INSTALLED_KUBECTL_VERSION="$(kubectl version --client 2>/dev/null | grep -oE 'v1\.[0-9]+\.[0-9]+' | head -1 || true)"
if [ "${INSTALLED_KUBECTL_VERSION}" != "${KUBECTL_VERSION}" ]; then
  echo "==> Installing kubectl ${KUBECTL_VERSION}..."
  curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
else
  echo "==> kubectl already installed: ${INSTALLED_KUBECTL_VERSION}"
fi

# ---- kind ----
# Always (re)install the pinned kind version so the node image below is
# guaranteed compatible - kind does not guarantee older/newer CLI versions
# work correctly with a given node image.
CURRENT_KIND_VERSION="$(kind version 2>/dev/null | awk '{print $2}' || true)"
if [ "${CURRENT_KIND_VERSION}" != "${KIND_VERSION}" ]; then
  echo "==> Installing kind ${KIND_VERSION}..."
  curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
else
  echo "==> kind already installed: $(kind version)"
fi

# ---- kind cluster config: 1 control-plane + 2 workers, Kubernetes v1.34 ----
cat > /tmp/kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
    image: ${NODE_IMAGE}
  - role: worker
    image: ${NODE_IMAGE}
  - role: worker
    image: ${NODE_IMAGE}
EOF

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> kind cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  echo "==> Creating kind cluster '${CLUSTER_NAME}' (1 control-plane + 2 workers)..."
  kind create cluster --config /tmp/kind-config.yaml
fi

echo "==> Cluster nodes:"
kubectl get nodes -o wide

echo "==> Cluster version:"
kubectl version

echo ""
echo "==> Done. Cluster context: kind-${CLUSTER_NAME}"
echo "==> Next: run ./02-create-issues-round1.sh to seed dev/test namespaces with broken workloads."