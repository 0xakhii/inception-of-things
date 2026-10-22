#!/bin/bash
# ──────────────────────────────────────────────────
# P3 — Cleanup: delete cluster and port-forwards
# ──────────────────────────────────────────────────

set -euo pipefail

echo "[P3] Stopping any port-forward processes..."
pkill -f "kubectl port-forward" 2>/dev/null || true

echo "[P3] Deleting K3d cluster 'iot'..."
k3d cluster delete iot 2>/dev/null || true

echo "[P3] Cleanup complete."

