#!/bin/bash
# ──────────────────────────────────────────────────
# Part 3 — Install all required tools
# Docker, K3d, kubectl
# ──────────────────────────────────────────────────

set -euo pipefail

echo "============================================="
echo " [P3] Installing required tools"
echo "============================================="

# ── Docker ──
if ! command -v docker &>/dev/null; then
  echo "[P3] Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
  echo "[P3] Docker installed. You may need to log out and back in for group changes."
else
  echo "[P3] Docker already installed."
fi

# ── kubectl ──
if ! command -v kubectl &>/dev/null; then
  echo "[P3] Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
else
  echo "[P3] kubectl already installed."
fi

# ── K3d ──
if ! command -v k3d &>/dev/null; then
  echo "[P3] Installing K3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
  echo "[P3] K3d already installed."
fi


echo "============================================="
echo " [P3] All tools installed!"
echo "============================================="
echo "  Docker:  $(docker --version 2>/dev/null || echo 'not found')"
echo "  kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
echo "  K3d:     $(k3d version 2>/dev/null | head -1)"

# ── Pre-pull Container Images (for faster, offline setup) ──
echo ""
echo "============================================="
echo " [P3] Pre-pulling container images to host"
echo "============================================="
ARGOCD_VERSION="v2.14.11"
IMAGES=(
  "quay.io/argoproj/argocd:${ARGOCD_VERSION}"
  "redis:7.0.15-alpine"
  "0xakhi/portfolio:v1"
)

for img in "${IMAGES[@]}"; do
  echo "  Pulling: ${img}"
  docker pull "${img}" || true
done
echo "[P3] All images pre-pulled to host Docker daemon!"
