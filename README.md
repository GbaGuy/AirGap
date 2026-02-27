# AirGap

Fully air-gapped Kubernetes deployment stack: **nginx ingress + ArgoCD + Harbor** — no internet required on the target cluster.

## Overview

This project provides scripts to bootstrap a Kubernetes cluster (kind or bare-metal) with:

- **nginx ingress controller** — routes traffic into the cluster
- **ArgoCD** — GitOps continuous delivery
- **Harbor** — private container registry

Everything can run completely offline by pre-downloading Docker images and manifests on a machine with internet, then loading them into containerd via `ctr` on the air-gapped machine.

## Project Structure

```
├── kind-config.yaml               # kind cluster config (hostPort 8080/443)
├── helms/airgap/                   # Sample Helm chart
├── offline/                        # Offline artifacts (images, manifests, charts)
│   ├── images/                     # Docker image tarballs (created by save script)
│   ├── nginx-ingress.yaml          # nginx manifest (created by save script)
│   ├── argocd-install.yaml         # ArgoCD manifest (created by save script)
│   ├── harbor-*.tgz               # Harbor Helm chart (created by save script)
│   ├── airgap-manifests.yaml       # Pre-rendered airgap chart manifests
│   └── airgap-0.1.0.tgz           # Packaged airgap Helm chart
└── scripts/
    ├── save-offline-images.sh      # Download all images & artifacts (run ONLINE)
    ├── install-offline-full.sh     # Full offline install (run AIR-GAPPED)
    ├── install-argocd-offline.sh   # Offline ArgoCD + nginx install
    ├── install-harbor-offline.sh   # Offline Harbor install
    ├── bootstrap-cluster.sh        # Online: recreate kind cluster + full stack
    ├── install-nginx.sh            # Online: install nginx ingress
    ├── install-argocd.sh           # Online: install ArgoCD
    ├── install-harbor.sh           # Online: install Harbor
    ├── install-metallb.sh          # Online: install MetalLB
    ├── install-airgap-offline.sh   # Offline Helm/kubectl install for airgap chart
    └── deploy-airgap.sh            # Deploy airgap chart via ArgoCD
```

## Quick Start (Online)

If you have internet access and want to bootstrap everything in one shot:

```bash
scripts/bootstrap-cluster.sh
```

This recreates the kind cluster with port mappings and installs nginx → ArgoCD → Harbor.

## Air-Gapped Install

### Step 1: Save images (on a machine WITH internet)

```bash
scripts/save-offline-images.sh
```

This downloads all Docker images, Helm charts, and manifests into `offline/`.

### Step 2: Transfer to air-gapped machine

Copy the entire repository (including `offline/`) to the target machine via USB, SCP, etc.

### Step 3: Install (on the air-gapped machine)

```bash
scripts/install-offline-full.sh
```

Or install components individually:

```bash
scripts/install-argocd-offline.sh    # nginx + ArgoCD
scripts/install-harbor-offline.sh    # Harbor
```

### How images are loaded

The scripts auto-detect the environment and use the appropriate method:

| Environment | Import method |
|---|---|
| kind cluster | `docker exec kind-control-plane ctr -n k8s.io images import <tar>` |
| Bare-metal / VM | `sudo ctr -n k8s.io images import <tar>` |

Override auto-detection with `USE_KIND=yes` or `USE_KIND=no`.

## Configuration

Key environment variables (all have sensible defaults):

| Variable | Default | Description |
|---|---|---|
| `HARBOR_VERSION` | `1.16.0` | Harbor Helm chart version |
| `ARGOCD_VERSION` | `stable` | ArgoCD manifest version |
| `NGINX_VERSION` | `v1.12.0` | nginx ingress controller version |
| `HARBOR_HOSTNAME` | `harbor.local` | Harbor ingress hostname |
| `ARGOCD_HOSTNAME` | `argocd.local` | ArgoCD ingress hostname |
| `HARBOR_ADMIN_PASSWORD` | `Harbor12345` | Harbor admin password |
| `USE_KIND` | `auto` | Force kind mode (`yes`/`no`/`auto`) |
| `KIND_NODE` | `kind-control-plane` | kind node container name |

## Access

After install, add these to `/etc/hosts` (done automatically by the full install script):

```
127.0.0.1  argocd.local
127.0.0.1  harbor.local
127.0.0.1  notary.local
```

| Service | URL | Credentials |
|---|---|---|
| ArgoCD | http://argocd.local:8080 | admin / (auto-generated, printed at install) |
| Harbor | http://harbor.local:8080 | admin / Harbor12345 |

## Requirements

- **Online machine**: `docker`, `helm`, `curl`
- **Air-gapped machine**: `kubectl`, `helm`, `ctr` (containerd) or `docker` (for kind)
- **kind clusters**: `kind` + `docker`
