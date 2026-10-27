#!/bin/bash
# ──────────────────────────────────────────────
# Worker provisioning script
# Installs K3s in agent mode and joins the server
# ──────────────────────────────────────────────

set -euo pipefail

echo "============================================="
echo " [ojamalSW] Installing K3s Agent"
echo "============================================="

# Check if curl is installed
if ! command -v curl &>/dev/null; then
  apt-get update
  apt-get install -y curl
fi


# Install K3s in agent mode
# --node-ip          bind to the private network IP (not NAT)
# --flannel-iface    use the correct interface for pod networking
# K3S_URL            points to the server's API endpoint
# K3S_TOKEN          shared secret to join the cluster
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="agent \
    --node-ip ${WORKER_IP} \
    --flannel-iface eth1" \
  sh -

echo "============================================="
echo " [ojamalSW] K3s Agent installed and joined!"
echo "============================================="
