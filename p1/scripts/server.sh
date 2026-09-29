#!/bin/bash
# ──────────────────────────────────────────────
# Server provisioning script
# Installs K3s in controller (server) mode
# ──────────────────────────────────────────────

set -euo pipefail

echo "============================================="
echo " [ojamalS] Installing K3s Server"
echo "============================================="

# Check if curl is installed
if ! command -v curl &>/dev/null; then
  apt-get update
  apt-get install -y curl
fi

# Create 1GB swap to prevent OOM
# if [ ! -f /swapfile ]; then
#   echo "[ojamalS] Creating 1GB swap..."
#   fallocate -l 1G /swapfile
#   chmod 600 /swapfile
#   mkswap /swapfile
#   swapon /swapfile
#   echo '/swapfile none swap sw 0 0' >> /etc/fstab
# fi

# Install K3s in server mode
# --write-kubeconfig-mode 644   allows kubectl without sudo
# --node-ip                     bind to the private network IP (not NAT)
# --flannel-iface               use the correct interface for pod networking
curl -sfL https://get.k3s.io | \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="server \
    --write-kubeconfig-mode 644 \
    --node-ip ${SERVER_IP} \
    --tls-san ${SERVER_IP} \
    --disable=traefik \
    --disable=metrics-server \
    --disable-helm-controller \
    --disable=servicelb \
    --flannel-iface eth1" \
  sh -

# journalctl -u k3s --no-pager -n 50   

# Wait for K3s to be ready
echo "[ojamalS] Waiting for K3s server to be ready..."
until kubectl get nodes &>/dev/null; do
  sleep 2
done

echo "============================================="
echo " [ojamalS] K3s Server is ready!"
echo "============================================="
kubectl get nodes -o wide
