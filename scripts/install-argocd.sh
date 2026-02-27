#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# ArgoCD Installation Script
# Installs nginx ingress controller + ArgoCD into a
# Kubernetes cluster and exposes ArgoCD via Ingress.
# Requirements: kubectl
# -------------------------------------------------------

ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"   # Override by exporting ARGOCD_VERSION
ARGOCD_HOSTNAME="${ARGOCD_HOSTNAME:-argocd.local}"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Checking prerequisites..."
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH." >&2
  exit 1
fi

# ---------- nginx ingress controller ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/install-nginx.sh"

# ---------- ArgoCD ----------
echo "==> Creating namespace '${ARGOCD_NAMESPACE}' (if it doesn't exist)..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ArgoCD (version: ${ARGOCD_VERSION})..."
kubectl apply --server-side --force-conflicts -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_MANIFEST_URL}"

echo "==> Patching argocd-server to run in insecure (HTTP) mode for ingress termination..."
kubectl patch deployment argocd-server \
  -n "${ARGOCD_NAMESPACE}" \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]' \
  2>/dev/null || true   # idempotent – ignore if flag already present

echo "==> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=300s

# ---------- Ingress ----------
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

# ---------- Credentials ----------
echo "==> Retrieving initial admin password..."
INITIAL_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n "${ARGOCD_NAMESPACE}" \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "==> ArgoCD installed successfully!"
echo ""
echo "    Ingress host : http://${ARGOCD_HOSTNAME}"
echo "    Username     : admin"
echo "    Password     : ${INITIAL_PASSWORD}"
echo ""
echo "    If testing locally, add this to /etc/hosts:"
INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "<INGRESS_IP>")
echo "      ${INGRESS_IP}  ${ARGOCD_HOSTNAME}"
echo ""
echo "    IMPORTANT: Change the admin password after first login!"
