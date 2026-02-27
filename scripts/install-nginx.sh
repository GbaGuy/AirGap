#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Nginx Ingress Controller Installation Script
# Installs the nginx ingress controller using the kind-
# specific manifest which enables hostPort (80/443) so
# traffic flows: WSL2 host:8080 → kind node:80 → nginx → services.
# Requirements: kubectl
# -------------------------------------------------------

NGINX_VERSION="${NGINX_VERSION:-v1.12.0}"
# kind-specific deploy binds hostPort 80/443 on the node and
# tolerates the control-plane taint — required for kind clusters.
NGINX_MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

echo "==> Installing nginx ingress controller for kind (${NGINX_VERSION})..."
kubectl apply --server-side --force-conflicts -f "${NGINX_MANIFEST_URL}"

echo "==> Waiting for nginx ingress controller deployment to roll out..."
kubectl rollout status deployment/ingress-nginx-controller \
  -n ingress-nginx --timeout=300s

echo "==> Waiting for nginx ingress controller pod to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "==> Nginx ingress controller installed successfully (hostPort 8080/443)."
