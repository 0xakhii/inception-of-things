#!/bin/bash
# ──────────────────────────────────────────────────
# Part 3 — Setup K3d cluster + Argo CD + App
# Minimal approach: pre-loads images, uses official
# ArgoCD manifests, no CLI dependency.
# ──────────────────────────────────────────────────

set -euo pipefail

CLUSTER_NAME="iot"
ARGOCD_NS="argocd"
DEV_NS="dev"
APP_NAME="portfolio"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFS_DIR="${SCRIPT_DIR}/../confs"

# ── ArgoCD images (from the stable install.yaml manifest) ──
ARGOCD_VERSION="v2.14.11"
ARGOCD_IMAGES=(
  "quay.io/argoproj/argocd:${ARGOCD_VERSION}"
  "redis:7.0.15-alpine"
)
APP_IMAGE="0xakhi/portfolio:v1"

echo "============================================="
echo " [P3] Setting up K3d + Argo CD"
echo "============================================="

# ── Delete existing cluster if present ──
if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  echo "[P3] Deleting existing cluster '${CLUSTER_NAME}'..."
  k3d cluster delete "${CLUSTER_NAME}"
fi

# ─────────────────────────────────────────────────
# 1. Create K3d cluster
# ─────────────────────────────────────────────────
echo "[P3] Creating K3d cluster..."
k3d cluster create "${CLUSTER_NAME}" \
  -p "8888:8888@loadbalancer" \
  -p "8080:80@loadbalancer" \
  --wait

echo "[P3] Cluster created. Waiting for nodes..."
kubectl wait --for=condition=ready node --all --timeout=120s

# ─────────────────────────────────────────────────
# 2. Import cached images into K3d
# ─────────────────────────────────────────────────
echo "[P3] Importing cached images into K3d cluster..."
k3d image import \
  "${ARGOCD_IMAGES[@]}" \
  "${APP_IMAGE}" \
  -c "${CLUSTER_NAME}"

# ─────────────────────────────────────────────────
# 3. Create namespaces
# ─────────────────────────────────────────────────
echo "[P3] Creating namespaces..."
kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "${DEV_NS}" --dry-run=client -o yaml | kubectl apply -f -

# ─────────────────────────────────────────────────
# 4. Install Argo CD via official manifest (Lightweight)
# ─────────────────────────────────────────────────
echo "[P3] Installing Argo CD..."
kubectl apply -n "${ARGOCD_NS}" --server-side=true \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

# Scale down unneeded workloads (Dex SSO, Notifications, ApplicationSet)
echo "[P3] Scaling down unneeded Argo CD components..."
kubectl scale deployment -n "${ARGOCD_NS}" argocd-dex-server --replicas=0
kubectl scale deployment -n "${ARGOCD_NS}" argocd-notifications-controller --replicas=0 2>/dev/null || true
kubectl scale deployment -n "${ARGOCD_NS}" argocd-applicationset-controller --replicas=0 2>/dev/null || true

# Configure fast Git polling and insecure (HTTP) mode
kubectl patch configmap argocd-cm -n "${ARGOCD_NS}" \
  --type merge -p '{"data": {"timeout.reconciliation": "10s"}}'
kubectl patch configmap argocd-cmd-params-cm -n "${ARGOCD_NS}" \
  --type merge -p '{"data": {"server.insecure": "true"}}'

# Wait for Argo CD server to be ready
echo "[P3] Waiting for Argo CD to be ready (this may take a few minutes)..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NS}" --timeout=300s

# ── Get Argo CD admin password ──
ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo "============================================="
echo " Argo CD Admin Credentials"
echo "============================================="
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo "============================================="
echo ""

# ─────────────────────────────────────────────────
# 5. Deploy ArgoCD Application (pure kubectl)
# ─────────────────────────────────────────────────
echo "[P3] Creating Argo CD application..."
kubectl apply -f "${CONFS_DIR}/argocd-app.yaml"

# Wait for the app to sync using kubectl (no ArgoCD CLI needed)
echo "[P3] Waiting for application to sync..."
for i in $(seq 1 60); do
  SYNC=$(kubectl get application "${APP_NAME}" -n "${ARGOCD_NS}" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  HEALTH=$(kubectl get application "${APP_NAME}" -n "${ARGOCD_NS}" \
    -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  if [ "${SYNC}" = "Synced" ] && [ "${HEALTH}" = "Healthy" ]; then
    echo "[P3] Application is Synced and Healthy!"
    break
  fi
  echo "  Sync: ${SYNC:-Pending} | Health: ${HEALTH:-Pending} (${i}/60)"
  sleep 5
done

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
echo "  Argo CD UI:  kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "               then open http://localhost:8080 (admin / ${ARGOCD_PASSWORD})"
echo "  App:         http://localhost:8888"
echo ""

echo "[P3] Testing app..."
sleep 2
curl -s http://localhost:8888/ && echo ""
echo ""
echo "Done! Use 'curl http://localhost:8888/' to test the app."
