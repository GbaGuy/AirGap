#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Offline Harbor Installation Script
# Loads Harbor Docker images into containerd via ctr and
# installs Harbor from a local Helm chart — NO internet.
#
# Pre-requisites on air-gapped machine:
#   - kubectl, helm
#   - containerd (or kind cluster)
#   - offline/ directory with images + chart from
#     save-offline-images.sh
#
# Requirements: kubectl, helm, ctr (or docker+kind)
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="${SCRIPT_DIR}/../offline"

HARBOR_NAMESPACE="${HARBOR_NAMESPACE:-harbor}"
HARBOR_VERSION="${HARBOR_VERSION:-1.16.0}"
HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-harbor.local}"
HARBOR_NOTARY_HOSTNAME="${HARBOR_NOTARY_HOSTNAME:-notary.local}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345}"
HARBOR_STORAGE_CLASS="${HARBOR_STORAGE_CLASS:-standard}"

CHART_PACKAGE="${OFFLINE_DIR}/harbor-${HARBOR_VERSION}.tgz"
IMAGES_DIR="${OFFLINE_DIR}/images"

# Detect if running inside a kind cluster
KIND_NODE="${KIND_NODE:-kind-control-plane}"
USE_KIND="${USE_KIND:-auto}"   # auto | yes | no

detect_kind() {
  if [[ "${USE_KIND}" == "yes" ]]; then return 0; fi
  if [[ "${USE_KIND}" == "no" ]]; then return 1; fi
  # auto-detect
  if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${KIND_NODE}$"; then
    return 0
  fi
  return 1
}

# ==========================================================
# Import a single image tarball into containerd
# ==========================================================
import_image() {
  local tar_file="$1"

  if detect_kind; then
    # kind cluster: exec into the kind node container
    docker cp "${tar_file}" "${KIND_NODE}:/tmp/$(basename "${tar_file}")"
    docker exec "${KIND_NODE}" ctr -n k8s.io images import "/tmp/$(basename "${tar_file}")"
    docker exec "${KIND_NODE}" rm -f "/tmp/$(basename "${tar_file}")"
  else
    # Bare-metal / VM with containerd
    sudo ctr -n k8s.io images import "${tar_file}"
  fi
}

# ==========================================================
# Validation
# ==========================================================
echo "==> Checking prerequisites..."
for cmd in kubectl helm; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: '${cmd}' is not installed or not in PATH." >&2
    exit 1
  fi
done

if [[ ! -f "${CHART_PACKAGE}" ]]; then
  echo "ERROR: Harbor chart not found at ${CHART_PACKAGE}" >&2
  echo "       Run save-offline-images.sh on an online machine first." >&2
  exit 1
fi

if [[ ! -d "${IMAGES_DIR}" ]]; then
  echo "ERROR: Images directory not found at ${IMAGES_DIR}" >&2
  exit 1
fi

if detect_kind; then
  echo "    Detected kind cluster (node: ${KIND_NODE})"
  echo "    Will use: docker exec ${KIND_NODE} ctr -n k8s.io images import"
else
  echo "    Bare-metal mode"
  echo "    Will use: sudo ctr -n k8s.io images import"
  if ! command -v ctr &>/dev/null; then
    echo "ERROR: 'ctr' not found. Is containerd installed?" >&2
    exit 1
  fi
fi

# ==========================================================
# 1. Load Harbor images into containerd
# ==========================================================
echo ""
echo "==> Loading Harbor images into containerd..."

HARBOR_TARS=$(find "${IMAGES_DIR}" -name 'goharbor_*.tar' -type f 2>/dev/null || true)
if [[ -z "${HARBOR_TARS}" ]]; then
  echo "WARNING: No Harbor image tarballs found (goharbor_*.tar)."
  echo "         Loading ALL image tarballs instead..."
  HARBOR_TARS=$(find "${IMAGES_DIR}" -name '*.tar' -type f)
fi

LOADED=0
while IFS= read -r tar_file; do
  echo "    [LOAD] $(basename "${tar_file}")"
  import_image "${tar_file}"
  LOADED=$((LOADED + 1))
done <<< "${HARBOR_TARS}"

echo "    Loaded ${LOADED} image(s)."

# ==========================================================
# 2. Create namespace
# ==========================================================
echo ""
echo "==> Creating namespace '${HARBOR_NAMESPACE}' (if it doesn't exist)..."
kubectl create namespace "${HARBOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ==========================================================
# 3. Install Harbor from local chart
# ==========================================================
echo ""
echo "==> Installing Harbor from local chart: ${CHART_PACKAGE}"
helm upgrade --install harbor "${CHART_PACKAGE}" \
  --namespace "${HARBOR_NAMESPACE}" \
  --wait \
  --timeout 10m \
  --set expose.type=ingress \
  --set expose.ingress.hosts.core="${HARBOR_HOSTNAME}" \
  --set expose.ingress.hosts.notary="${HARBOR_NOTARY_HOSTNAME}" \
  --set expose.ingress.className=nginx \
  --set expose.tls.enabled=false \
  --set externalURL="http://${HARBOR_HOSTNAME}:8080" \
  --set harborAdminPassword="${HARBOR_ADMIN_PASSWORD}" \
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.registry.storageClass="${HARBOR_STORAGE_CLASS}" \
  --set persistence.persistentVolumeClaim.jobservice.jobLog.storageClass="${HARBOR_STORAGE_CLASS}" \
  --set persistence.persistentVolumeClaim.database.storageClass="${HARBOR_STORAGE_CLASS}" \
  --set persistence.persistentVolumeClaim.redis.storageClass="${HARBOR_STORAGE_CLASS}" \
  --set persistence.persistentVolumeClaim.trivy.storageClass="${HARBOR_STORAGE_CLASS}"

# ==========================================================
# Done
# ==========================================================
echo ""
echo "==> Harbor installed successfully (offline)!"
echo ""
echo "    Core URL  : http://${HARBOR_HOSTNAME}:8080"
echo "    Username  : admin"
echo "    Password  : ${HARBOR_ADMIN_PASSWORD}"
echo ""
echo "    Add to /etc/hosts:"
echo "      127.0.0.1  ${HARBOR_HOSTNAME}"
echo "      127.0.0.1  ${HARBOR_NOTARY_HOSTNAME}"
