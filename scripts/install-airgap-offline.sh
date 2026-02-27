#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Offline Helm Install Script
# Installs the airgap Helm chart from a local .tgz package
# — no internet access or Helm repo required.
#
# Two install modes:
#   1) helm install  (default) — uses the packaged .tgz
#   2) kubectl apply — uses pre-rendered manifests
#      Set MODE=kubectl to use this fallback.
#
# Requirements: helm (or kubectl for MODE=kubectl)
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="${SCRIPT_DIR}/../offline"

MODE="${MODE:-helm}"          # helm | kubectl
RELEASE_NAME="${RELEASE_NAME:-airgap}"
NAMESPACE="${NAMESPACE:-airgap}"

CHART_PACKAGE="${OFFLINE_DIR}/airgap-0.1.0.tgz"
MANIFESTS_FILE="${OFFLINE_DIR}/airgap-manifests.yaml"

# ---------- Validation ----------
if [[ "${MODE}" == "helm" ]]; then
  if ! command -v helm &>/dev/null; then
    echo "ERROR: helm is not installed. Set MODE=kubectl to use kubectl instead." >&2
    exit 1
  fi
  if [[ ! -f "${CHART_PACKAGE}" ]]; then
    echo "ERROR: Chart package not found at ${CHART_PACKAGE}" >&2
    echo "       Run: helm package helms/airgap/ -d offline/" >&2
    exit 1
  fi
else
  if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl is not installed." >&2
    exit 1
  fi
  if [[ ! -f "${MANIFESTS_FILE}" ]]; then
    echo "ERROR: Manifests file not found at ${MANIFESTS_FILE}" >&2
    exit 1
  fi
fi

# ---------- Create namespace ----------
echo "==> Creating namespace '${NAMESPACE}' (if it doesn't exist)..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ---------- Install ----------
if [[ "${MODE}" == "helm" ]]; then
  echo "==> Installing chart from local package: ${CHART_PACKAGE}"
  helm upgrade --install "${RELEASE_NAME}" "${CHART_PACKAGE}" \
    --namespace "${NAMESPACE}" \
    --set ingress.enabled=true \
    --set ingress.className=nginx
else
  echo "==> Applying pre-rendered manifests: ${MANIFESTS_FILE}"
  kubectl apply -f "${MANIFESTS_FILE}" -n "${NAMESPACE}"
fi

echo ""
echo "==> Offline install complete!"
echo ""
echo "    Release   : ${RELEASE_NAME}"
echo "    Namespace : ${NAMESPACE}"
echo "    Mode      : ${MODE}"
