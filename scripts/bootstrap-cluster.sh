#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Cluster Bootstrap Script (WSL2 + kind)
# Recreates the kind cluster with proper extraPortMappings
# (8080/443) so nginx ingress hostPort binds work, then
# installs: nginx → ArgoCD → Harbor
#
# WARNING: This deletes the existing 'kind' cluster!
# Requirements: kind, kubectl, helm
# -------------------------------------------------------

CLUSTER_NAME="${CLUSTER_NAME:-kind}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CONFIG="${SCRIPT_DIR}/../kind-config.yaml"

echo "==> Checking prerequisites..."
for cmd in kind kubectl helm; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: '${cmd}' is not installed or not in PATH." >&2
    exit 1
  fi
done

# ---------- Recreate cluster ----------
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "==> Deleting existing kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
fi

echo "==> Creating kind cluster '${CLUSTER_NAME}' with extraPortMappings (8080/443)..."
kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"

echo "==> Cluster ready. Current context: $(kubectl config current-context)"

# ---------- Install stack ----------
echo ""
echo "==> [1/3] Installing nginx ingress controller..."
bash "${SCRIPT_DIR}/install-nginx.sh"

echo ""
echo "==> [2/3] Installing ArgoCD..."
bash "${SCRIPT_DIR}/install-argocd.sh"

echo ""
echo "==> [3/3] Installing Harbor..."
bash "${SCRIPT_DIR}/install-harbor.sh"

echo ""
echo "==> Stack: nginx → ArgoCD → Harbor (no MetalLB — kind uses hostPort)"

# ---------- /etc/hosts ----------
echo ""
echo "==> Ensuring /etc/hosts entries are correct..."
NODE_IP="127.0.0.1"   # extraPortMappings bind to WSL2 localhost

for HOST in argocd.local harbor.local notary.local; do
  if grep -q "${HOST}" /etc/hosts; then
    sudo sed -i "s/.*${HOST}/${NODE_IP}  ${HOST}/" /etc/hosts
  else
    echo "${NODE_IP}  ${HOST}" | sudo tee -a /etc/hosts > /dev/null
  fi
done

echo ""
echo "=================================================="
echo " Bootstrap complete!"
echo "=================================================="
echo ""
echo "  ArgoCD : http://argocd.local"
echo "  Harbor : http://harbor.local"
echo ""
echo "  ArgoCD admin password:"
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
echo ""
echo "  Harbor admin password : Harbor12345"
echo "=================================================="
