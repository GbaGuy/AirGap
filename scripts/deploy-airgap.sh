#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Deploy AirGap Helm Chart via ArgoCD
# Creates an ArgoCD Application that points to the airgap
# Helm chart in this repository.
# Requirements: kubectl, ArgoCD installed in the cluster
# -------------------------------------------------------

ARGOCD_NAMESPACE="argocd"
APP_NAME="${APP_NAME:-airgap}"
APP_NAMESPACE="${APP_NAMESPACE:-airgap}"
REPO_URL="${REPO_URL:-https://github.com/GbaGuy/AirGap.git}"
TARGET_REVISION="${TARGET_REVISION:-HEAD}"
CHART_PATH="helms/airgap"

echo "==> Checking prerequisites..."
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH." >&2
  exit 1
fi

if ! kubectl get namespace "${ARGOCD_NAMESPACE}" &>/dev/null; then
  echo "ERROR: ArgoCD namespace '${ARGOCD_NAMESPACE}' not found. Is ArgoCD installed?" >&2
  exit 1
fi

# ---------- Create target namespace ----------
echo "==> Creating namespace '${APP_NAMESPACE}' (if it doesn't exist)..."
kubectl create namespace "${APP_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ---------- Deploy ArgoCD Application ----------
echo "==> Deploying ArgoCD Application '${APP_NAME}'..."
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: ${ARGOCD_NAMESPACE}
spec:
  project: default
  source:
    repoURL: "${REPO_URL}"
    targetRevision: ${TARGET_REVISION}
    path: ${CHART_PATH}
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${APP_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "==> Waiting for ArgoCD to sync the application..."
kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
  "application/${APP_NAME}" \
  -n "${ARGOCD_NAMESPACE}" \
  --timeout=300s 2>/dev/null || true

echo ""
echo "==> ArgoCD Application '${APP_NAME}' deployed!"
echo ""
echo "    App name   : ${APP_NAME}"
echo "    Namespace  : ${APP_NAMESPACE}"
echo "    Repo       : ${REPO_URL}"
echo "    Chart path : ${CHART_PATH}"
echo "    Revision   : ${TARGET_REVISION}"
echo ""
echo "    View in ArgoCD UI: http://argocd.local:8080/applications/${APP_NAME}"
