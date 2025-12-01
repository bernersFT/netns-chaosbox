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
CONFIG_FILE="${SCRIPT_DIR}/chaosbox.conf"
PLACEHOLDER="__REQUIRED_CHANGE_ME__"

# Create chaosbox.conf template if missing
if [[ ! -f "${CONFIG_FILE}" ]]; then
  log "Config file '${CONFIG_FILE}' not found. Creating a template..."
  cat > "${CONFIG_FILE}" <<EOF
# Chaosbox user configuration
# YOU MUST edit these values before running Chaosbox.
# If any of them keep the placeholder value, Chaosbox will refuse to start.

# Outbound interface used for Internet access (VERY IMPORTANT)
# Example: "ens4", "eth0", "enp0s3"
WAN_DEV="__REQUIRED_CHANGE_ME__"

# Egress IP address of WAN_DEV in CIDR format (VERY IMPORTANT)
# Example: "192.168.3.254/24"
WAN_DEV_IP="__REQUIRED_CHANGE_ME__"

# Management networks that MUST NOT go through the chaos path (VERY IMPORTANT)
# Example:
#   MGMT_NET1="192.168.1.0/24"
#   MGMT_NET2="172.16.0.0/24"
MGMT_NET1="__REQUIRED_CHANGE_ME__"
MGMT_NET2="__REQUIRED_CHANGE_ME__"
EOF

  log "A config template has been created at: ${CONFIG_FILE}"
  log "Please edit this file, set proper values, and re-run ./install.sh."
  exit 0
fi

# If file exists, ensure user has edited it (no placeholders left)
if grep -q "${PLACEHOLDER}" "${CONFIG_FILE}"; then
  err "Config file '${CONFIG_FILE}' still contains placeholder values (${PLACEHOLDER})."
  err "Please edit this file and replace ALL placeholders with real values, then re-run ./install.sh."
  exit 1
fi

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
