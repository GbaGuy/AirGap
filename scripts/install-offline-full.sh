#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Full Offline Bootstrap Script
# Loads ALL Docker images into containerd via ctr, then
# installs the full stack: nginx → ArgoCD → Harbor
# — completely air-gapped, NO internet required.
#
# Usage:
#   1. On an ONLINE machine, run:  scripts/save-offline-images.sh
#   2. Copy the entire repo (with offline/) to the air-gapped machine
#   3. On the AIR-GAPPED machine, run:  scripts/install-offline-full.sh
#
# For kind clusters the script auto-detects the kind node
# and uses: docker exec <node> ctr -n k8s.io images import
#
# For bare-metal / VM with containerd it uses:
#   sudo ctr -n k8s.io images import
#
# Requirements: kubectl, helm, ctr (or docker+kind)
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="${SCRIPT_DIR}/../offline"
IMAGES_DIR="${OFFLINE_DIR}/images"

CLUSTER_NAME="${CLUSTER_NAME:-kind}"
KIND_NODE="${KIND_NODE:-${CLUSTER_NAME}-control-plane}"
USE_KIND="${USE_KIND:-auto}"

export KIND_NODE USE_KIND

detect_kind() {
  if [[ "${USE_KIND}" == "yes" ]]; then return 0; fi
  if [[ "${USE_KIND}" == "no" ]]; then return 1; fi
  if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${KIND_NODE}$"; then
    return 0
  fi
  return 1
}

import_image() {
  local tar_file="$1"
  if detect_kind; then
    docker cp "${tar_file}" "${KIND_NODE}:/tmp/$(basename "${tar_file}")"
    docker exec "${KIND_NODE}" ctr -n k8s.io images import "/tmp/$(basename "${tar_file}")"
    docker exec "${KIND_NODE}" rm -f "/tmp/$(basename "${tar_file}")"
  else
    sudo ctr -n k8s.io images import "${tar_file}"
  fi
}

# ==========================================================
# Validation
# ==========================================================
echo "=========================================="
echo " Air-Gapped Full Offline Install"
echo "=========================================="
echo ""

echo "==> Checking prerequisites..."
for cmd in kubectl helm; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: '${cmd}' is not installed or not in PATH." >&2
    exit 1
  fi
done

if [[ ! -d "${IMAGES_DIR}" ]]; then
  echo "ERROR: Images directory not found at ${IMAGES_DIR}" >&2
  echo "       Run save-offline-images.sh on an online machine first." >&2
  exit 1
fi

for f in nginx-ingress.yaml argocd-install.yaml; do
  if [[ ! -f "${OFFLINE_DIR}/${f}" ]]; then
    echo "ERROR: ${f} not found in ${OFFLINE_DIR}" >&2
    exit 1
  fi
done

HARBOR_CHART=$(find "${OFFLINE_DIR}" -maxdepth 1 -name 'harbor-*.tgz' -type f | head -1)
if [[ -z "${HARBOR_CHART}" ]]; then
  echo "ERROR: Harbor chart .tgz not found in ${OFFLINE_DIR}" >&2
  exit 1
fi

if detect_kind; then
  echo "    Mode: kind cluster (node: ${KIND_NODE})"
  echo "    Import method: docker exec ${KIND_NODE} ctr -n k8s.io images import"
else
  echo "    Mode: bare-metal / VM"
  echo "    Import method: sudo ctr -n k8s.io images import"
  if ! command -v ctr &>/dev/null; then
    echo "ERROR: 'ctr' not found. Is containerd installed?" >&2
    exit 1
  fi
fi

# ==========================================================
# 1. Load ALL images into containerd
# ==========================================================
echo ""
echo "==> [1/4] Loading all Docker images into containerd..."
TOTAL=$(find "${IMAGES_DIR}" -name '*.tar' -type f | wc -l)
LOADED=0

for tar_file in "${IMAGES_DIR}"/*.tar; do
  [[ -f "${tar_file}" ]] || continue
  LOADED=$((LOADED + 1))
  echo "    [${LOADED}/${TOTAL}] $(basename "${tar_file}")"
  import_image "${tar_file}"
done

echo "    Done — ${LOADED} image(s) loaded."

# ==========================================================
# 2. Install nginx ingress controller
# ==========================================================
echo ""
echo "==> [2/4] Installing nginx ingress controller (offline)..."
kubectl apply --server-side --force-conflicts -f "${OFFLINE_DIR}/nginx-ingress.yaml"

echo "    Waiting for nginx ingress controller..."
kubectl rollout status deployment/ingress-nginx-controller \
  -n ingress-nginx --timeout=300s

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "    nginx ingress ready."

# ==========================================================
# 3. Install ArgoCD
# ==========================================================
echo ""
echo "==> [3/4] Installing ArgoCD (offline)..."
bash "${SCRIPT_DIR}/install-argocd-offline.sh"

# ==========================================================
# 4. Install Harbor
# ==========================================================
echo ""
echo "==> [4/4] Installing Harbor (offline)..."
bash "${SCRIPT_DIR}/install-harbor-offline.sh"

# ==========================================================
# /etc/hosts
# ==========================================================
echo ""
echo "==> Ensuring /etc/hosts entries..."
NODE_IP="127.0.0.1"

for HOST in argocd.local harbor.local notary.local; do
  if grep -q "${HOST}" /etc/hosts; then
    sudo sed -i "s/.*${HOST}/${NODE_IP}  ${HOST}/" /etc/hosts
  else
    echo "${NODE_IP}  ${HOST}" | sudo tee -a /etc/hosts > /dev/null
  fi
done

# ==========================================================
# Summary
# ==========================================================
ARGOCD_PW=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "(pending)")

echo ""
echo "=========================================="
echo " Offline Bootstrap Complete!"
echo "=========================================="
echo ""
echo "  ArgoCD"
echo "    URL      : http://argocd.local:8080"
echo "    Username : admin"
echo "    Password : ${ARGOCD_PW}"
echo ""
echo "  Harbor"
echo "    URL      : http://harbor.local:8080"
echo "    Username : admin"
echo "    Password : ${HARBOR_ADMIN_PASSWORD:-Harbor12345}"
echo ""
echo "  All images were loaded via ctr into containerd."
echo "  No internet access was required."
echo "=========================================="
