#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Nginx Ingress Controller Installation Script
# Installs the nginx ingress controller and patches its
# service to ClusterIP (suitable for air-gapped / bare-metal).
# Requirements: kubectl
# -------------------------------------------------------

NGINX_VERSION="${NGINX_VERSION:-v1.12.0}"
NGINX_MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml"

echo "==> Installing nginx ingress controller (${NGINX_VERSION})..."
kubectl apply --server-side --force-conflicts -f "${NGINX_MANIFEST_URL}"

echo "==> Patching ingress-nginx-controller service to ClusterIP..."
kubectl patch svc ingress-nginx-controller \
  -n ingress-nginx \
  --type='merge' \
  -p='{"spec":{"type":"ClusterIP","externalTrafficPolicy":null}}'

echo "==> Waiting for nginx ingress controller to be ready..."
kubectl rollout status deployment/ingress-nginx-controller \
  -n ingress-nginx --timeout=300s

echo "==> Nginx ingress controller installed successfully (ClusterIP)."
