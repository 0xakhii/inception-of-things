#!/bin/bash
# ──────────────────────────────────────────────────
# Bonus — Cleanup: delete cluster and port-forwards
# ──────────────────────────────────────────────────

set -euo pipefail

echo "[BONUS] Stopping any port-forward processes..."
pkill -f "kubectl port-forward" 2>/dev/null || true

echo "[BONUS] Deleting K3d cluster 'iot'..."
k3d cluster delete iot 2>/dev/null || true

echo "[BONUS] Cleanup complete."

