#!/bin/bash
# ──────────────────────────────────────────────────
# Part 2 — Server provisioning script
# Installs K3s and deploys 3 web apps with Ingress
# ──────────────────────────────────────────────────

set -euo pipefail

echo "============================================="
echo " [ojamalS] Installing K3s Server (Part 2)"
echo "============================================="

# Install curl if missing
if ! command -v curl &>/dev/null; then
  apt-get update
  apt-get install -y curl
fi

# Create 1GB swap to prevent OOM
if [ ! -f /swapfile ]; then
  echo "[ojamalS] Creating 1GB swap..."
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Install K3s in server mode
curl -sfL https://get.k3s.io | \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="server \
    --write-kubeconfig-mode 644 \
    --node-ip ${SERVER_IP} \
    --tls-san ${SERVER_IP} \
    --flannel-iface eth1" \
  sh -

# Wait for K3s to be ready
echo "[ojamalS] Waiting for K3s to be ready..."
until kubectl get nodes &>/dev/null; do
  sleep 2
done

# Wait for Traefik (Ingress controller) to be deployed by K3s
echo "[ojamalS] Waiting for Traefik pod to appear..."
while [ "$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers 2>/dev/null | wc -l)" -eq 0 ]; do
  sleep 5
done

echo "[ojamalS] Waiting for Traefik to be ready..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=traefik \
  --timeout=300s

# Pre-pull container images so deploys don't wait on runtime pulls
echo "[ojamalS] Pre-pulling app images..."
k3s ctr images pull docker.io/wil42/playground:v2
k3s ctr images pull docker.io/library/nginx:alpine
k3s ctr images pull docker.io/0xakhi/portfolio:latest

# Deploy the 3 apps
echo "[ojamalS] Deploying applications..."
kubectl apply -f /vagrant/confs/

echo "============================================="
echo " [ojamalS] All apps deployed!"
echo "============================================="
kubectl get all
kubectl get ingress
