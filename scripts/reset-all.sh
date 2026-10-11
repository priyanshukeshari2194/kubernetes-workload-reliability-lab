#!/usr/bin/env bash
# reset-all.sh — complete lab teardown and optional rebuild
# =========================================================
# This script removes every resource created by the lab and optionally
# rebuilds from scratch.  Run it when you want a completely clean slate.
#
# Usage:
#   bash scripts/reset-all.sh           # teardown only
#   bash scripts/reset-all.sh --rebuild # teardown then rebuild
#
# What is removed:
#   - The reliability-lab Kubernetes namespace (and everything in it)
#   - The kind cluster named "reliability-lab"
#
# What is NOT removed:
#   - The Docker image in the local Docker daemon (use `docker rmi` manually)
#   - WSL2 itself or Docker Engine
#   - Python packages installed by pip install -r requirements-dev.txt
#
# After this script completes, re-run:
#   make deploy-all

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-reliability-lab}"
REBUILD="${1:-}"

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

echo ""
printf "${BOLD}Reliability Lab — Full Reset${RESET}\n"
echo ""

# Step 1: Delete the namespace (removes all namespaced resources)
printf "${BOLD}Step 1/2 — Deleting namespace 'reliability-lab'...${RESET}\n"
kubectl delete namespace reliability-lab --ignore-not-found --timeout=60s || true
printf "${GREEN}Namespace deleted (or was not present).${RESET}\n"

# Step 2: Delete the kind cluster
printf "${BOLD}Step 2/2 — Deleting kind cluster '%s'...${RESET}\n" "$CLUSTER_NAME"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  kind delete cluster --name "$CLUSTER_NAME"
  printf "${GREEN}Cluster deleted.${RESET}\n"
else
  printf "${YELLOW}Cluster '%s' not found — nothing to delete.${RESET}\n" "$CLUSTER_NAME"
fi

echo ""
printf "${GREEN}${BOLD}Reset complete.${RESET}\n"

if [[ "$REBUILD" == "--rebuild" ]]; then
  echo ""
  printf "${BOLD}Rebuilding from scratch...${RESET}\n"
  make deploy-all
fi
