#!/usr/bin/env bash
# wsl-setup.sh — one-shot installer for all lab prerequisites inside WSL2
# ========================================================================
# Run this ONCE in a fresh WSL2 (Ubuntu) terminal:
#   bash scripts/wsl-setup.sh
#
# What this script installs:
#   - Docker Engine (NOT Docker Desktop — the free CLI daemon in WSL2)
#   - kind   (Kubernetes IN Docker)
#   - kubectl
#   - Python 3 dev tools (pip, venv)
#
# What this script does NOT do:
#   - Install Docker Desktop (optional, paid for commercial use)
#   - Connect to any cloud provider
#   - Require root on the Windows host — only uses WSL2-internal sudo
#
# After running this script, start Docker Engine:
#   sudo service docker start
#   newgrp docker          # add yourself to the docker group without re-login
#
# Then run the lab:
#   make deploy-all

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# Detect distro (supports Ubuntu/Debian only; add others as needed)
if ! grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
  printf "${YELLOW}Warning: This script is tested on Ubuntu/Debian. Adjust package manager commands for other distros.${RESET}\n"
fi

echo ""
printf "${BOLD}Step 1/4 — Update apt package lists${RESET}\n"
sudo apt-get update -qq

echo ""
printf "${BOLD}Step 2/4 — Install Docker Engine (local, no cloud)${RESET}\n"
if command -v docker &>/dev/null; then
  printf "${GREEN}docker already installed: $(docker --version)${RESET}\n"
else
  # Official Docker install script — runs entirely locally
  sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  sudo usermod -aG docker "$USER"
  printf "${GREEN}Docker Engine installed.${RESET}\n"
  printf "${YELLOW}Run 'newgrp docker' or log out/in to use docker without sudo.${RESET}\n"
fi

echo ""
printf "${BOLD}Step 3/4 — Install kind${RESET}\n"
if command -v kind &>/dev/null; then
  printf "${GREEN}kind already installed: $(kind version)${RESET}\n"
else
  KIND_VERSION="v0.24.0"
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  KIND_ARCH="amd64" ;;
    aarch64) KIND_ARCH="arm64" ;;
    *)       printf "Unsupported architecture: %s\n" "$ARCH"; exit 1 ;;
  esac
  curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${KIND_ARCH}" \
    -o /tmp/kind
  chmod +x /tmp/kind
  sudo mv /tmp/kind /usr/local/bin/kind
  printf "${GREEN}kind $(kind version) installed.${RESET}\n"
fi

echo ""
printf "${BOLD}Step 4/4 — Install kubectl${RESET}\n"
if command -v kubectl &>/dev/null; then
  printf "${GREEN}kubectl already installed: $(kubectl version --client 2>&1 | head -1)${RESET}\n"
else
  # Install the version that matches or is compatible with kind's bundled k8s
  KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /tmp/kubectl
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin/kubectl
  printf "${GREEN}kubectl $(kubectl version --client 2>&1 | head -1) installed.${RESET}\n"
fi

echo ""
printf "${GREEN}${BOLD}All prerequisites installed.${RESET}\n"
echo ""
printf "Next steps:\n"
printf "  1. sudo service docker start\n"
printf "  2. newgrp docker\n"
printf "  3. bash scripts/check-tools.sh\n"
printf "  4. make deploy-all\n"
echo ""
