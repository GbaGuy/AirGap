#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Harbor Registry Installation Script
# Installs Harbor container registry via Helm into a
# Kubernetes cluster and exposes it via Ingress.
# Requirements: kubectl, helm
# -------------------------------------------------------

HARBOR_NAMESPACE="${HARBOR_NAMESPACE:-harbor}"
HARBOR_VERSION="${HARBOR_VERSION:-1.16.0}"
HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-harbor.local}"
HARBOR_NOTARY_HOSTNAME="${HARBOR_NOTARY_HOSTNAME:-notary.local}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345}"
HARBOR_STORAGE_CLASS="${HARBOR_STORAGE_CLASS:-standard}"

echo "==> Checking prerequisites..."
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH." >&2
  exit 1
fi
if ! command -v helm &>/dev/null; then
  echo "ERROR: helm is not installed or not in PATH." >&2
  exit 1
fi

# ---------- Helm repo ----------
echo "==> Adding Harbor Helm repository..."
helm repo add harbor https://helm.goharbor.io
helm repo update

# ---------- Namespace ----------
echo "==> Creating namespace '${HARBOR_NAMESPACE}' (if it doesn't exist)..."
kubectl create namespace "${HARBOR_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ---------- Install ----------
echo "==> Installing Harbor (version: ${HARBOR_VERSION})..."
helm upgrade --install harbor harbor/harbor \
  --namespace "${HARBOR_NAMESPACE}" \
  --version "${HARBOR_VERSION}" \
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

# ---------- /etc/hosts hint ----------
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

echo ""
echo "==> Harbor installed successfully!"
echo ""
echo "    Core URL  : http://${HARBOR_HOSTNAME}"
echo "    Username  : admin"
echo "    Password  : ${HARBOR_ADMIN_PASSWORD}"
echo ""
if [[ -n "${INGRESS_IP}" ]]; then
  echo "    Add the following entries to /etc/hosts:"
  echo "      ${INGRESS_IP}  ${HARBOR_HOSTNAME}"
  echo "      ${INGRESS_IP}  ${HARBOR_NOTARY_HOSTNAME}"
else
  echo "    Add harbor.local and notary.local to /etc/hosts pointing to your ingress IP."
  echo "    Run: kubectl get svc -n ingress-nginx ingress-nginx-controller"
fi
