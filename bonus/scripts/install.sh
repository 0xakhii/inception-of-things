#!/bin/bash
# ──────────────────────────────────────────────────
# Bonus — Install all required tools
# Docker, K3d, kubectl, Argo CD CLI, Helm
# ──────────────────────────────────────────────────

set -euo pipefail

echo "============================================="
echo " [BONUS] Installing required tools"
echo "============================================="

# ── Docker ──
if ! command -v docker &>/dev/null; then
  echo "[BONUS] Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
  echo "[BONUS] Docker installed. You may need to log out and back in for group changes."
else
  echo "[BONUS] Docker already installed."
fi

# ── kubectl ──
if ! command -v kubectl &>/dev/null; then
  echo "[BONUS] Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
else
  echo "[BONUS] kubectl already installed."
fi

# ── K3d ──
if ! command -v k3d &>/dev/null; then
  echo "[BONUS] Installing K3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
  echo "[BONUS] K3d already installed."
fi

# ── Argo CD CLI ──
if ! command -v argocd &>/dev/null; then
  echo "[BONUS] Installing Argo CD CLI..."
  curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
  rm -f argocd-linux-amd64
else
  echo "[BONUS] Argo CD CLI already installed."
fi

# ── Helm ──
if ! command -v helm &>/dev/null; then
  echo "[BONUS] Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "[BONUS] Helm already installed."
fi

echo "============================================="
echo " [BONUS] All tools installed!"
echo "============================================="
echo "  Docker:  $(docker --version 2>/dev/null || echo 'not found')"
echo "  kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
echo "  K3d:     $(k3d version 2>/dev/null | head -1)"
echo "  ArgoCD:  $(argocd version --client --short 2>/dev/null || echo 'not found')"
echo "  Helm:    $(helm version --short 2>/dev/null || echo 'not found')"
