#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# MetalLB Installation Script
# Installs MetalLB load-balancer and configures an
# IPAddressPool for bare-metal / kind clusters.
# Requirements: kubectl
# -------------------------------------------------------

METALLB_VERSION="${METALLB_VERSION:-v0.14.9}"
METALLB_MANIFEST_URL="https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

# IP range to allocate for LoadBalancer services (adjust to match your network)
METALLB_IP_RANGE="${METALLB_IP_RANGE:-172.20.0.100-172.20.0.120}"

echo "==> Installing MetalLB (${METALLB_VERSION})..."
kubectl apply -f "${METALLB_MANIFEST_URL}"

echo "==> Waiting for MetalLB controller to be ready..."
kubectl rollout status deployment/controller \
  -n metallb-system --timeout=300s

echo "==> Waiting for MetalLB webhook service to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=component=controller \
  --timeout=120s

echo "==> Configuring IPAddressPool (${METALLB_IP_RANGE})..."
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - ${METALLB_IP_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
EOF

echo "==> MetalLB installed and configured successfully."
echo "    IP pool: ${METALLB_IP_RANGE}"
