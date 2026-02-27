#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Offline ArgoCD Installation Script
# Loads ArgoCD + nginx ingress Docker images into
# containerd via ctr and installs from local manifests
# — NO internet required.
#
# Pre-requisites on air-gapped machine:
#   - kubectl
#   - containerd (or kind cluster)
#   - offline/ directory with images + manifests from
#     save-offline-images.sh
#
# Requirements: kubectl, ctr (or docker+kind)
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="${SCRIPT_DIR}/../offline"

ARGOCD_NAMESPACE="argocd"
ARGOCD_HOSTNAME="${ARGOCD_HOSTNAME:-argocd.local}"

NGINX_MANIFEST="${OFFLINE_DIR}/nginx-ingress.yaml"
ARGOCD_MANIFEST="${OFFLINE_DIR}/argocd-install.yaml"
IMAGES_DIR="${OFFLINE_DIR}/images"

# Detect if running inside a kind cluster
KIND_NODE="${KIND_NODE:-kind-control-plane}"
USE_KIND="${USE_KIND:-auto}"   # auto | yes | no

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
echo "==> Checking prerequisites..."
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH." >&2
  exit 1
fi

if [[ ! -f "${NGINX_MANIFEST}" ]]; then
  echo "ERROR: nginx manifest not found at ${NGINX_MANIFEST}" >&2
  echo "       Run save-offline-images.sh on an online machine first." >&2
  exit 1
fi

if [[ ! -f "${ARGOCD_MANIFEST}" ]]; then
  echo "ERROR: ArgoCD manifest not found at ${ARGOCD_MANIFEST}" >&2
  echo "       Run save-offline-images.sh on an online machine first." >&2
  exit 1
fi

if [[ ! -d "${IMAGES_DIR}" ]]; then
  echo "ERROR: Images directory not found at ${IMAGES_DIR}" >&2
  exit 1
fi

if detect_kind; then
  echo "    Detected kind cluster (node: ${KIND_NODE})"
else
  echo "    Bare-metal mode"
  if ! command -v ctr &>/dev/null; then
    echo "ERROR: 'ctr' not found. Is containerd installed?" >&2
    exit 1
  fi
fi

# ==========================================================
# 1. Load ALL images into containerd
# ==========================================================
echo ""
echo "==> Loading images into containerd..."

LOADED=0
for tar_file in "${IMAGES_DIR}"/*.tar; do
  [[ -f "${tar_file}" ]] || continue
  echo "    [LOAD] $(basename "${tar_file}")"
  import_image "${tar_file}"
  LOADED=$((LOADED + 1))
done

echo "    Loaded ${LOADED} image(s)."

# ==========================================================
# 2. Install nginx ingress controller (from local manifest)
# ==========================================================
echo ""
echo "==> Installing nginx ingress controller (offline)..."
kubectl apply --server-side --force-conflicts -f "${NGINX_MANIFEST}"

echo "==> Waiting for nginx ingress controller to be ready..."
kubectl rollout status deployment/ingress-nginx-controller \
  -n ingress-nginx --timeout=300s

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "    nginx ingress controller ready."

# ==========================================================
# 3. Install ArgoCD (from local manifest)
# ==========================================================
echo ""
echo "==> Creating namespace '${ARGOCD_NAMESPACE}' (if it doesn't exist)..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ArgoCD (offline)..."
kubectl apply --server-side --force-conflicts -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_MANIFEST}"

echo "==> Patching argocd-server for insecure (HTTP) mode..."
kubectl patch deployment argocd-server \
  -n "${ARGOCD_NAMESPACE}" \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]' \
  2>/dev/null || true

echo "==> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=300s

# ==========================================================
# 4. Create ArgoCD Ingress
# ==========================================================
echo ""
echo "==> Applying ArgoCD Ingress (host: ${ARGOCD_HOSTNAME})..."
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: ${ARGOCD_NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
    - host: ${ARGOCD_HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

# ==========================================================
# 5. Print credentials
# ==========================================================
echo ""
echo "==> Retrieving initial admin password..."
INITIAL_PASSWORD=""
for i in {1..30}; do
  INITIAL_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
    -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || true)
  if [[ -n "${INITIAL_PASSWORD}" ]]; then break; fi
  sleep 2
done

echo ""
echo "==> ArgoCD installed successfully (offline)!"
echo ""
echo "    Ingress host : http://${ARGOCD_HOSTNAME}:8080"
echo "    Username     : admin"
if [[ -n "${INITIAL_PASSWORD}" ]]; then
  echo "    Password     : ${INITIAL_PASSWORD}"
else
  echo "    Password     : (not ready yet — run: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)"
fi
echo ""
echo "    Add to /etc/hosts:"
echo "      127.0.0.1  ${ARGOCD_HOSTNAME}"
echo ""
echo "    IMPORTANT: Change the admin password after first login!"
