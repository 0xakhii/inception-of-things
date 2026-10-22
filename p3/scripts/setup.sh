#!/bin/bash
# ──────────────────────────────────────────────────
# Part 3 — Setup K3d cluster + Argo CD + App
# ──────────────────────────────────────────────────

set -euo pipefail

CLUSTER_NAME="iot"
ARGOCD_NS="argocd"
DEV_NS="dev"
GITHUB_REPO="https://github.com/0xakhii/Portfolio.git"
APP_NAME="portfolio"

echo "============================================="
echo " [P3] Setting up K3d + Argo CD"
echo "============================================="

# ── Delete existing cluster if present ──
if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  echo "[P3] Deleting existing cluster '${CLUSTER_NAME}'..."
  k3d cluster delete "${CLUSTER_NAME}"
fi

# ── Create K3d cluster ──
# Map port 8888 on host to port 8888 on the load balancer
# Map port 8080 on host to port 80 on the load balancer (for Argo CD UI)
echo "[P3] Creating K3d cluster..."
k3d cluster create "${CLUSTER_NAME}" \
  -p "8888:8888@loadbalancer" \
  -p "8080:80@loadbalancer" \
  --wait

echo "[P3] Cluster created. Waiting for nodes..."
kubectl wait --for=condition=ready node --all --timeout=120s

# ── Create namespaces ──
echo "[P3] Creating namespaces..."
kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "${DEV_NS}" --dry-run=client -o yaml | kubectl apply -f -

# ── Install Argo CD ──
echo "[P3] Installing Argo CD..."
kubectl apply -n "${ARGOCD_NS}" --server-side=true -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Configure fast Git polling (10s instead of default 3 minutes)
kubectl patch configmap argocd-cm -n "${ARGOCD_NS}" --type merge -p '{"data": {"timeout.reconciliation": "10s"}}'

# Wait for Argo CD pods to be ready
echo "[P3] Waiting for Argo CD to be ready (this may take a few minutes)..."
kubectl wait --namespace "${ARGOCD_NS}" \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=300s

# ── Get Argo CD admin password ──
ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo "============================================="
echo " Argo CD Admin Credentials"
echo "============================================="
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo "============================================="
echo ""

# ── Expose Argo CD server via port-forward (background) ──
echo "[P3] Starting Argo CD port-forward on localhost:8443..."
kubectl port-forward svc/argocd-server -n "${ARGOCD_NS}" 8443:443 &>/dev/null &
PORT_FWD_PID=$!
sleep 3

# ── Login to Argo CD ──
echo "[P3] Logging into Argo CD..."
argocd login localhost:8443 \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --insecure

# ── Create the Argo CD Application ──
echo "[P3] Creating Argo CD application..."
kubectl apply -f ${HOME}/inception-of-things/p3/confs/argocd-app.yaml

# ── Wait for the app to sync ──
echo "[P3] Waiting for application to sync..."
argocd app wait "${APP_NAME}" --timeout 120 || true

# ── Show status ──
echo ""
echo "============================================="
echo " [P3] Setup Complete!"
echo "============================================="
echo ""
kubectl get ns
echo ""
kubectl get pods -n "${DEV_NS}"
echo ""
kubectl get svc -n "${DEV_NS}"
echo ""
echo "  Argo CD UI:  https://localhost:8443 (admin / ${ARGOCD_PASSWORD})"
echo "  App:         http://localhost:8888"
echo ""

echo "[P3] Testing app..."
sleep 2
curl -s http://localhost:8888/ && echo ""
echo ""
echo "Done! Use 'curl http://localhost:8888/' to test the app."
