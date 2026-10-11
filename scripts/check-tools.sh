#!/usr/bin/env bash
# check-tools.sh — verify all prerequisites for the Reliability Lab
# ==================================================================
# Run inside WSL2:  bash scripts/check-tools.sh
# Or via Makefile:  make check-tools   (which calls this script)
#
# Exit codes:
#   0 — all required tools found
#   1 — one or more required tools missing
#
# This script intentionally avoids `set -e` so it can report ALL missing
# tools in one run rather than stopping at the first failure.

set -uo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

MISSING=0

check_tool() {
  local tool="$1"
  local min_version_hint="$2"
  local path
  path=$(command -v "$tool" 2>/dev/null || true)

  if [[ -n "$path" ]]; then
    local version
    version=$("$tool" version 2>/dev/null | head -1 || "$tool" --version 2>/dev/null | head -1 || echo "version unknown")
    printf "  ${GREEN}✓${RESET} %-12s  %s\n" "$tool" "$version"
  else
    printf "  ${RED}✗${RESET} %-12s  ${RED}NOT FOUND${RESET}  (min: %s)\n" "$tool" "$min_version_hint"
    MISSING=1
  fi
}

echo ""
printf "${BOLD}Checking required tools (must be inside WSL2):${RESET}\n"
check_tool "docker"  "27.x"
check_tool "kind"    "0.24.x"
check_tool "kubectl" "1.28+"
check_tool "python3" "3.11+"
check_tool "git"     "2.40+"

echo ""
printf "${BOLD}Checking optional tools:${RESET}\n"
check_tool "make"    "4.x"
check_tool "curl"    "any"
check_tool "jq"      "1.6+"

echo ""

# ---- Docker daemon check ---------------------------------------------------
printf "${BOLD}Checking Docker daemon:${RESET}\n"
if docker info &>/dev/null; then
  printf "  ${GREEN}✓${RESET} Docker daemon is running\n"
else
  printf "  ${RED}✗${RESET} Docker daemon is NOT running\n"
  printf "    ${YELLOW}Fix: start Docker Engine in WSL2:${RESET}\n"
  printf "         sudo service docker start\n"
  printf "    ${YELLOW}Or enable Docker Desktop's WSL2 backend from Docker Desktop settings.${RESET}\n"
  MISSING=1
fi

echo ""

# ---- WSL2 check (only meaningful if run from PowerShell via wsl) -----------
if grep -qi "microsoft" /proc/version 2>/dev/null; then
  printf "${GREEN}✓ Running inside WSL2 kernel.${RESET}\n"
else
  printf "${YELLOW}⚠ Not running inside WSL2. Some scripts assume the WSL2 environment.${RESET}\n"
fi

echo ""

if [[ "$MISSING" -eq 0 ]]; then
  printf "${GREEN}${BOLD}All required tools found. Ready to run: make deploy-all${RESET}\n"
  exit 0
else
  printf "${RED}${BOLD}One or more required tools are missing. See docs/setup.md for installation instructions.${RESET}\n"
  exit 1
fi
