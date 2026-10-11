#!/usr/bin/env bash
# cluster-create.sh — create a local kind cluster for the Reliability Lab
# ========================================================================
# Usage (called by Makefile):
#   bash scripts/cluster-create.sh <cluster-name> <kind-config-path>
#
# Usage (directly in WSL2 terminal):
#   bash scripts/cluster-create.sh reliability-lab scripts/kind-config.yaml
#
# This script:
#   1. Checks if a cluster with the given name already exists.
#   2. If it exists, reports it and exits cleanly (idempotent).
#   3. If not, creates it with the provided kind config.
#   4. Verifies the cluster is reachable with kubectl.
#
# NO CLOUD PROVIDER IS USED. The cluster runs entirely in a Docker container
# on your local machine inside WSL2.

set -euo pipefail

CLUSTER_NAME="${1:-reliability-lab}"
KIND_CONFIG="${2:-scripts/kind-config.yaml}"

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

echo ""
printf "${BOLD}Reliability Lab — Local kind Cluster Setup${RESET}\n"
printf "Cluster name : %s\n" "$CLUSTER_NAME"
printf "kind config  : %s\n" "$KIND_CONFIG"
echo ""

# ---- Check if cluster already exists ---------------------------------------
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  printf "${YELLOW}Cluster '%s' already exists. Skipping creation.${RESET}\n" "$CLUSTER_NAME"
  printf "Current kubectl context:\n"
  kubectl config current-context
  echo ""
  printf "${GREEN}Use 'make cluster-delete' to remove it, or 'make deploy' to redeploy.${RESET}\n"
  exit 0
fi

# ---- Create the cluster ----------------------------------------------------
printf "${BOLD}Creating kind cluster '%s'...${RESET}\n" "$CLUSTER_NAME"
kind create cluster \
  --name "$CLUSTER_NAME" \
  --config "$KIND_CONFIG" \
  --wait 120s

echo ""
printf "${BOLD}Verifying cluster connectivity...${RESET}\n"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo ""
printf "${BOLD}Node status:${RESET}\n"
kubectl get nodes

echo ""
printf "${GREEN}${BOLD}Cluster ready.${RESET}\n"
printf "Next step: ${BOLD}make build load deploy${RESET}\n"
printf "Or all at once: ${BOLD}make deploy-all${RESET}\n"
echo ""

# ---- Install metrics-server (optional, for kubectl top) --------------------
# metrics-server is required for Scenario B observation (kubectl top pods).
# We install the local-only version that does not require TLS verification
# (kind does not have a real certificate for the kubelet's HTTPS endpoint).
# If this fails, the lab still works — Scenario B can be observed via
# kubectl describe pod (which reads from the API server, not metrics-server).
echo ""
printf "${YELLOW}Attempting to install metrics-server (optional, needed for 'kubectl top')...${RESET}\n"
if kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>/dev/null; then
  # Patch the deployment to add --kubelet-insecure-tls (required for kind)
  kubectl patch deployment metrics-server \
    -n kube-system \
    --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
    2>/dev/null && \
    printf "${GREEN}metrics-server installed with --kubelet-insecure-tls for kind.${RESET}\n" || true
else
  printf "${YELLOW}metrics-server install skipped (no internet or apply failed).${RESET}\n"
  printf "kubectl top pods will not work, but all other lab features are unaffected.\n"
fi
