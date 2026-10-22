#!/bin/bash
# ──────────────────────────────────────────────────
# Bonus — Setup K3d + Argo CD + GitLab + App
#
# This script:
#   1. Creates a K3d cluster
#   2. Installs Argo CD
#   3. Installs GitLab via Helm (minimal config)
#   4. Creates a GitLab project + pushes manifests
#   5. Configures Argo CD to sync from local GitLab
# ──────────────────────────────────────────────────

set -euo pipefail

# ── Variables ──
CLUSTER_NAME="iot"
ARGOCD_NS="argocd"
DEV_NS="dev"
GITLAB_NS="gitlab"
APP_NAME="portfolio"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFS_DIR="${SCRIPT_DIR}/../confs"
GITLAB_SVC="gitlab-webservice-default"
GITLAB_INTERNAL_URL="http://${GITLAB_SVC}.${GITLAB_NS}.svc.cluster.local:8080"

# Port-forward PIDs (for cleanup on exit)
PF_PIDS=()
cleanup_pf() {
  for pid in "${PF_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup_pf EXIT

# ─────────────────────────────────────────────────
# 1. Create K3d Cluster
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo " [BONUS] Step 1/7 — Creating K3d cluster"
echo "============================================="

k3d cluster delete "${CLUSTER_NAME}" 2>/dev/null || true

k3d cluster create "${CLUSTER_NAME}" \
  -p "8888:8888@loadbalancer" \
  -p "8080:80@loadbalancer" \
  --wait

echo "[BONUS] Waiting for nodes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=120s

# ─────────────────────────────────────────────────
# 2. Create Namespaces
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo " [BONUS] Step 2/7 — Creating namespaces"
echo "============================================="

for ns in "${ARGOCD_NS}" "${DEV_NS}" "${GITLAB_NS}"; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl get ns

# ─────────────────────────────────────────────────
# 3. Install Argo CD
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo " [BONUS] Step 3/7 — Installing Argo CD"
echo "============================================="

kubectl apply -n "${ARGOCD_NS}" --server-side=true \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Fast Git polling (10s instead of default 3 minutes)
kubectl patch configmap argocd-cm -n "${ARGOCD_NS}" \
  --type merge -p '{"data": {"timeout.reconciliation": "10s"}}'

echo "[BONUS] Waiting for Argo CD server to be ready..."
kubectl wait -n "${ARGOCD_NS}" \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=900s #Needs to be changed to 300s

ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "  ┌───────────────────────────────────────┐"
echo "  │  Argo CD:  admin / ${ARGOCD_PASSWORD}  "
echo "  └───────────────────────────────────────┘"
echo ""

# ─────────────────────────────────────────────────
# 4. Install GitLab via Helm
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo " [BONUS] Step 4/7 — Installing GitLab"
echo "   (this takes 5-10 minutes, be patient)"
echo "============================================="

helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
helm repo update

helm upgrade --install gitlab gitlab/gitlab \
  --namespace "${GITLAB_NS}" \
  -f "${CONFS_DIR}/gitlab-values.yaml" \
  --timeout 300s

echo "[BONUS] Waiting for GitLab webservice to be ready..."
# The webservice pod can take a while — retry with a generous timeout
for i in $(seq 1 10); do
  READY=$(kubectl get pods -n "${GITLAB_NS}" -l app=webservice \
    -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [ "$READY" = "True" ]; then
    echo "[BONUS] GitLab webservice is ready!"
    break
  fi
  echo "[BONUS]   Waiting for webservice... (${i}/10, checking every 2s)"
  sleep 2
done

echo "[BONUS] Waiting for GitLab toolbox to be ready..."
kubectl wait -n "${GITLAB_NS}" --for=condition=ready pod \
  -l app=toolbox --timeout=300s 2>/dev/null || true

# ─────────────────────────────────────────────────
# 5. Get GitLab Credentials + Create Access Token
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo " [BONUS] Step 5/7 — GitLab credentials"
echo "============================================="

GITLAB_REDIS_PASSWORD="${GITLAB_REDIS_PASSWORD:-$(openssl rand -hex 24)}"
GITLAB_POSTGRES_PASSWORD="${GITLAB_POSTGRES_PASSWORD:-$(openssl rand -hex 24)}"


kubectl create secret generic gitlab-redis-password \
  -n "${GITLAB_NS}" \
  --from-literal=redis-password="${GITLAB_REDIS_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gitlab-postgresql-password \
  -n "${GITLAB_NS}" \
  --from-literal=password="${GITLAB_POSTGRES_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -


GITLAB_ROOT_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password \
  -n "${GITLAB_NS}" -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "  ┌───────────────────────────────────────┐"
echo "  │  GitLab:  root / ${GITLAB_ROOT_PASSWORD}  "
echo "  └───────────────────────────────────────┘"
echo ""

echo "[BONUS] Creating GitLab personal access token via Rails console..."
GITLAB_TOKEN=$(kubectl exec -n "${GITLAB_NS}" deploy/gitlab-toolbox -- \
  gitlab-rails runner "
    user = User.find_by_username('root')
    token = user.personal_access_tokens.create!(
      name: 'iot-automation',
      scopes: [:api, :read_repository, :write_repository],
      expires_at: 365.days.from_now
    )
    print token.token
  " ) #2>/dev/null)

if [ -z "${GITLAB_TOKEN}" ]; then
  echo "[BONUS] ERROR: Failed to create GitLab token. Retrying in 30s..."
  sleep 30
  GITLAB_TOKEN=$(kubectl exec -n "${GITLAB_NS}" deploy/gitlab-toolbox -- \
    gitlab-rails runner "
      user = User.find_by_username('root')
      token = user.personal_access_tokens.create!(
        name: 'iot-automation-retry',
        scopes: [:api, :read_repository, :write_repository],
        expires_at: 365.days.from_now
      )
      print token.token
    " 2>/dev/null)
fi

echo "[BONUS] GitLab token created successfully."

# ─────────────────────────────────────────────────
# 6. Create GitLab Project + Push Manifests
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo " [BONUS] Step 6/7 — Creating GitLab repo"
echo "============================================="

# Port-forward GitLab webservice for API access
echo "[BONUS] Starting GitLab port-forward (localhost:8181 -> webservice:8080)..."
kubectl port-forward "svc/${GITLAB_SVC}" -n "${GITLAB_NS}" 8181:8080 &>/dev/null &
PF_PIDS+=($!)
sleep 5

# Wait for GitLab API to respond
echo "[BONUS] Waiting for GitLab API to be responsive..."
for i in $(seq 1 30); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:8181/api/v4/version" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    echo "[BONUS] GitLab API is ready!"
    break
  fi
  echo "[BONUS]   API not ready yet (HTTP ${HTTP_CODE})... (${i}/30)"
  sleep 10
done

# Create project
echo "[BONUS] Creating project 'portfolio'..."
CREATE_RESP=$(curl -s -X POST "http://localhost:8181/api/v4/projects" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "portfolio",
    "visibility": "public",
    "initialize_with_readme": true
  }')

# Extract project ID
PROJECT_ID=$(echo "$CREATE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
if [ -z "$PROJECT_ID" ]; then
  echo "[BONUS] Warning: Could not extract project ID. Project may already exist."
  PROJECT_ID=$(curl -s "http://localhost:8181/api/v4/projects/root%2Fportfolio" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "1")
fi
echo "[BONUS] Project ID: ${PROJECT_ID}"

sleep 3

# Push deployment.yaml via GitLab API
echo "[BONUS] Pushing deployment.yaml to GitLab..."
FILE_CONTENT=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    content = f.read()
payload = {
    'branch': 'main',
    'content': content,
    'commit_message': 'Add portfolio deployment manifests'
}
print(json.dumps(payload))
" "${CONFS_DIR}/deployment.yaml")

PUSH_RESP=$(curl -s -w "\n%{http_code}" -X POST \
  "http://localhost:8181/api/v4/projects/${PROJECT_ID}/repository/files/deployment.yaml" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${FILE_CONTENT}")

PUSH_CODE=$(echo "$PUSH_RESP" | tail -1)
if [ "$PUSH_CODE" = "201" ]; then
  echo "[BONUS] deployment.yaml pushed successfully!"
elif [ "$PUSH_CODE" = "400" ]; then
  echo "[BONUS] File already exists, updating..."
  FILE_CONTENT_UPDATE=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    content = f.read()
payload = {
    'branch': 'main',
    'content': content,
    'commit_message': 'Update portfolio deployment manifests'
}
print(json.dumps(payload))
" "${CONFS_DIR}/deployment.yaml")

  curl -s -X PUT \
    "http://localhost:8181/api/v4/projects/${PROJECT_ID}/repository/files/deployment.yaml" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${FILE_CONTENT_UPDATE}" >/dev/null
  echo "[BONUS] deployment.yaml updated!"
else
  echo "[BONUS] Warning: Unexpected response code ${PUSH_CODE}"
fi

# ─────────────────────────────────────────────────
# 7. Configure Argo CD → Local GitLab
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo " [BONUS] Step 7/7 — Connecting ArgoCD <-> GitLab"
echo "============================================="

# Port-forward ArgoCD
echo "[BONUS] Starting ArgoCD port-forward (localhost:8443)..."
kubectl port-forward svc/argocd-server -n "${ARGOCD_NS}" 8443:443 &>/dev/null &
PF_PIDS+=($!)
sleep 3

# Login to ArgoCD
echo "[BONUS] Logging into ArgoCD..."
argocd login localhost:8443 \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --insecure

# Add the local GitLab repo
REPO_URL="${GITLAB_INTERNAL_URL}/root/portfolio.git"
echo "[BONUS] Adding repo: ${REPO_URL}"
argocd repo add "${REPO_URL}" --insecure-skip-server-verification 2>/dev/null || true

# Create ArgoCD application
echo "[BONUS] Creating ArgoCD application..."
kubectl apply -f "${CONFS_DIR}/argocd-app.yaml"

# Wait for sync
echo "[BONUS] Waiting for application to sync..."
argocd app wait "${APP_NAME}" --timeout 120 || true

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
echo ""
echo "============================================="
echo "         [BONUS] Setup Complete!             "
echo "============================================="
echo ""
echo "  GitLab:    http://localhost:8181"
echo "    User:    root"
echo "    Pass:    ${GITLAB_ROOT_PASSWORD}"
echo ""
echo "  ArgoCD:    https://localhost:8443"
echo "    User:    admin"
echo "    Pass:    ${ARGOCD_PASSWORD}"
echo ""
echo "  App:       http://localhost:8888"
echo ""

echo "── Namespaces ──"
kubectl get ns
echo ""
echo "── GitLab Pods ──"
kubectl get pods -n "${GITLAB_NS}"
echo ""
echo "── App Pods ──"
kubectl get pods -n "${DEV_NS}"
echo ""
echo "── App Services ──"
kubectl get svc -n "${DEV_NS}"
echo ""

echo "[BONUS] Testing app..."
sleep 3
if curl -s --max-time 5 http://localhost:8888/ >/dev/null 2>&1; then
  echo "[BONUS] App is responding on http://localhost:8888"
else
  echo "[BONUS] App not responding yet — it may need a few more seconds"
fi

echo ""
echo "To verify the GitOps loop:"
echo "  1. Open GitLab: http://localhost:8181/root/portfolio"
echo "  2. Edit deployment.yaml (e.g. change replicas to 2)"
echo "  3. Wait ~10s for ArgoCD to pick up the change"
echo "  4. Run: kubectl get pods -n dev"
echo ""
echo "To clean up: bash ${SCRIPT_DIR}/cleanup.sh"

