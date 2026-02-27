#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# ArgoCD Installation Script
# Installs ArgoCD into a Kubernetes cluster.
# Requirements: kubectl, helm (optional)
# -------------------------------------------------------

ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"   # Override by exporting ARGOCD_VERSION
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Checking prerequisites..."
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH." >&2
  exit 1
fi

echo "==> Creating namespace '${ARGOCD_NAMESPACE}' (if it doesn't exist)..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ArgoCD (version: ${ARGOCD_VERSION})..."
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_MANIFEST_URL}"

echo "==> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=300s

echo "==> Retrieving initial admin password..."
INITIAL_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n "${ARGOCD_NAMESPACE}" \
  -o jsonpath="{.data.password}" | base64 -d)
echo "    Initial admin password: ${INITIAL_PASSWORD}"

echo ""
echo "==> ArgoCD installed successfully!"
echo "    To access the UI, run:"
echo "      kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
echo "    Then open: https://localhost:8080"
echo "    Username : admin"
echo "    Password : ${INITIAL_PASSWORD}"
echo ""
echo "    IMPORTANT: Change the admin password after first login!"
