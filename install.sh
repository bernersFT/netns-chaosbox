#!/usr/bin/env bash
set -euo pipefail

###############################################################
# Chaosbox Installer
# This script performs:
#   1) Build & run SoftEther VPN in Docker which support L2TP, IPsec, Openvpn and SoftEther VPN client
#   2) Run Chaosbox network simulation environment
#
# Expected directory structure:
#     netns-chaosbox/
#     ├ chaosbox/latest/run_chaosbox.sh
#     ├ docker/Dockerfile
#     ├ docker/docker-compose.yml
#     ├ docker/docker-entrypoint.sh
#     └ install.sh  (this script)
###############################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOCKER_DIR="${SCRIPT_DIR}/docker"
CHAOSBOX_RUN="${SCRIPT_DIR}/chaosbox/latest/run_chaosbox.sh"

###############################################################
# Helper functions
###############################################################
log() { echo "[install] $*"; }
err() { echo "[install][ERROR] $*" >&2; }

###############################################################
# Root permission check
###############################################################
if [[ $EUID -ne 0 ]]; then
  err "Please run this script as root (sudo ./install.sh)."
  exit 1
fi

###############################################################
# Check Docker environment
###############################################################
if ! command -v docker >/dev/null; then
  err "Docker is not installed. Please install Docker first."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  err "'docker compose' is not available. Install the Docker Compose plugin."
  exit 1
fi

log "Docker environment check passed."

###############################################################
# 1) Build & run SoftEther VPN Docker service
###############################################################
log "Switching to Docker directory: ${DOCKER_DIR}"
cd "${DOCKER_DIR}"

log "Stopping previous 'softvpn' container if exists..."
docker compose down || true

log "Building Docker image chaosbox/softether-vpn:latest ..."
DOCKER_BUILDKIT=0 docker compose build --no-cache --progress=plain

log "Image build completed. Starting the 'softvpn' container..."
docker compose up -d

log "SoftVPN container status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep softvpn || true

###############################################################
# 2) Run Chaosbox main runtime script
###############################################################
log "Preparing to run Chaosbox runtime script: ${CHAOSBOX_RUN}"

if [[ ! -x "${CHAOSBOX_RUN}" ]]; then
  err "Cannot find executable: ${CHAOSBOX_RUN}"
  exit 1
fi

log "Executing Chaosbox environment (run_chaosbox.sh)..."
"${CHAOSBOX_RUN}"

###############################################################
# Installation summary
###############################################################
cat <<EOF

-----------------------------------------------------
Chaosbox Installation Completed Successfully 🎉
-----------------------------------------------------

SoftEther VPN:
  - Container name: softvpn
  - Check status:
        docker ps | grep softvpn
  - Check logs:
        docker logs softvpn --tail=100

Chaosbox runtime:
  chaosbox/latest/run_chaosbox.sh has been executed.

Rollback:
  Use chaosbox/latest/rollback.sh if needed.

You may now start using Chaosbox and SoftEther VPN.

Both username and password are the same "chaosbox"

enjoy it!

-----------------------------------------------------
EOF
