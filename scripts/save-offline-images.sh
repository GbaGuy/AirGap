#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Save Offline Images & Artifacts
# Run this script on a machine WITH internet access.
# It downloads all Docker images, Helm charts, and
# manifests needed for a fully air-gapped install of:
#   - nginx ingress controller
#   - ArgoCD
#   - Harbor
#
# Output: offline/ directory with all tarballs & manifests
# Requirements: docker, helm, curl
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="${SCRIPT_DIR}/../offline"

HARBOR_VERSION="${HARBOR_VERSION:-1.16.0}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
NGINX_VERSION="${NGINX_VERSION:-v1.12.0}"

mkdir -p "${OFFLINE_DIR}/images"

echo "==> Checking prerequisites..."
for cmd in docker helm curl; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: '${cmd}' is not installed or not in PATH." >&2
    exit 1
  fi
done

# ==========================================================
# 1. Download manifests
# ==========================================================
echo ""
echo "==> [1/5] Downloading nginx ingress manifest..."
NGINX_MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"
curl -sSL -o "${OFFLINE_DIR}/nginx-ingress.yaml" "${NGINX_MANIFEST_URL}"
echo "    Saved: offline/nginx-ingress.yaml"

echo ""
echo "==> [2/5] Downloading ArgoCD manifest..."
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
curl -sSL -o "${OFFLINE_DIR}/argocd-install.yaml" "${ARGOCD_MANIFEST_URL}"
echo "    Saved: offline/argocd-install.yaml"

# ==========================================================
# 2. Download Harbor Helm chart
# ==========================================================
echo ""
echo "==> [3/5] Downloading Harbor Helm chart (${HARBOR_VERSION})..."
helm repo add harbor https://helm.goharbor.io 2>/dev/null || true
helm repo update
helm pull harbor/harbor --version "${HARBOR_VERSION}" -d "${OFFLINE_DIR}"
echo "    Saved: offline/harbor-${HARBOR_VERSION}.tgz"

# ==========================================================
# 3. Extract all image references
# ==========================================================
echo ""
echo "==> [4/5] Extracting image references from manifests and charts..."

IMAGES_FILE="${OFFLINE_DIR}/images-list.txt"
: > "${IMAGES_FILE}"

# --- nginx ingress images ---
grep -oP 'image:\s*"\K[^"]+' "${OFFLINE_DIR}/nginx-ingress.yaml" >> "${IMAGES_FILE}" || true
grep -oP 'image:\s*\K[^\s"]+' "${OFFLINE_DIR}/nginx-ingress.yaml" >> "${IMAGES_FILE}" || true

# --- ArgoCD images ---
grep -oP 'image:\s*\K[^\s"]+' "${OFFLINE_DIR}/argocd-install.yaml" >> "${IMAGES_FILE}" || true
grep -oP 'image:\s*"\K[^"]+' "${OFFLINE_DIR}/argocd-install.yaml" >> "${IMAGES_FILE}" || true

# --- Harbor images (from helm template) ---
helm template harbor "${OFFLINE_DIR}/harbor-${HARBOR_VERSION}.tgz" 2>/dev/null \
  | grep -oP 'image:\s*"\K[^"]+' >> "${IMAGES_FILE}" || true
helm template harbor "${OFFLINE_DIR}/harbor-${HARBOR_VERSION}.tgz" 2>/dev/null \
  | grep -oP 'image:\s*\K[^\s"]+' >> "${IMAGES_FILE}" || true

# Deduplicate and clean
sort -u "${IMAGES_FILE}" | grep -v '^$' | grep '/' > "${IMAGES_FILE}.tmp"
mv "${IMAGES_FILE}.tmp" "${IMAGES_FILE}"

IMAGE_COUNT=$(wc -l < "${IMAGES_FILE}")
echo "    Found ${IMAGE_COUNT} unique images:"
cat "${IMAGES_FILE}" | sed 's/^/      /'

# ==========================================================
# 4. Pull and save all images
# ==========================================================
echo ""
echo "==> [5/5] Pulling and saving Docker images..."

while IFS= read -r img; do
  # Create a safe filename from the image reference
  safe_name=$(echo "${img}" | tr '/:@' '_')
  tar_file="${OFFLINE_DIR}/images/${safe_name}.tar"

  if [[ -f "${tar_file}" ]]; then
    echo "    [SKIP] ${img} (already saved)"
    continue
  fi

  echo "    [PULL] ${img}"
  docker pull "${img}"

  echo "    [SAVE] ${img} -> images/${safe_name}.tar"
  docker save "${img}" -o "${tar_file}"
done < "${IMAGES_FILE}"

# ==========================================================
# Summary
# ==========================================================
TOTAL_SIZE=$(du -sh "${OFFLINE_DIR}" | awk '{print $1}')
echo ""
echo "=========================================="
echo " Offline artifacts saved successfully!"
echo "=========================================="
echo ""
echo "  Directory  : ${OFFLINE_DIR}"
echo "  Total size : ${TOTAL_SIZE}"
echo ""
echo "  Contents:"
echo "    - nginx-ingress.yaml     (nginx ingress manifest)"
echo "    - argocd-install.yaml    (ArgoCD manifest)"
echo "    - harbor-${HARBOR_VERSION}.tgz    (Harbor Helm chart)"
echo "    - images-list.txt        (image inventory)"
echo "    - images/                (Docker image tarballs)"
echo ""
echo "  Copy the entire offline/ directory to the air-gapped"
echo "  machine and run the install scripts."
echo "=========================================="
