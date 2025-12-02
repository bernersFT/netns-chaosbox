#!/usr/bin/env bash
set -euo pipefail

###############################################################
# Chaosbox + SoftEther VPN Installer
#
# Features:
#   - Require chaosbox.conf to be properly configured
#   - Read image from docker/docker-compose.yml
#   - Ask user whether to build image locally (default: NO)
#   - If NO: pull prebuilt image + comment out build section
#   - If YES: uncomment build section + build with docker compose
#   - Start softvpn container
#   - Run chaosbox/latest/run_chaosbox.sh if present
###############################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOCKER_DIR="${SCRIPT_DIR}/docker"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"
CHAOSBOX_RUN="${SCRIPT_DIR}/chaosbox/latest/run_chaosbox.sh"
CONFIG_FILE="${SCRIPT_DIR}/chaosbox.conf"
PLACEHOLDER="__REQUIRED_CHANGE_ME__"

log() { echo "[install] $*"; }
err() { echo "[install][ERROR] $*" >&2; }

###############################################################
# Basic checks
###############################################################
require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Please run this script as root (sudo ./install.sh)"
    exit 1
  fi
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    err "Docker is not installed. Please install Docker first."
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    err "'docker compose' is not available. Please install the Docker Compose plugin."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    err "Cannot talk to Docker daemon. Please ensure Docker is running."
    exit 1
  fi
}

###############################################################
# chaosbox.conf handling (MANDATORY)
###############################################################
ensure_config() {
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
# Example: "1.2.3.4/30"
WAN_DEV_IP="__REQUIRED_CHANGE_ME__"

# Management networks that MUST NOT go through the chaos path (VERY IMPORTANT)
# Example:
#   MGMT_NET1="10.146.0.0/16"
#   MGMT_NET2="10.145.0.0/16"
MGMT_NET1="__REQUIRED_CHANGE_ME__"
MGMT_NET2="__REQUIRED_CHANGE_ME__"
EOF

    log "A config template has been created at: ${CONFIG_FILE}"
    log "Please edit this file, set proper values, and re-run ./install.sh."
    exit 0
  fi

  if grep -q "${PLACEHOLDER}" "${CONFIG_FILE}"; then
    err "Config file '${CONFIG_FILE}' still contains placeholder value(s) (${PLACEHOLDER})."
    err "Please edit this file and replace ALL placeholders with real values, then re-run ./install.sh."
    exit 1
  fi

  log "Config file '${CONFIG_FILE}' looks valid (no placeholders)."
}

###############################################################
# docker-compose.yml helpers
###############################################################
get_image() {
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    err "docker-compose.yml not found at: ${COMPOSE_FILE}"
    exit 1
  fi

  local img
  img=$(awk '/^[[:space:]]*image:/ {print $2; exit}' "${COMPOSE_FILE}")
  if [[ -z "${img}" ]]; then
    err "Could not find an 'image:' entry in ${COMPOSE_FILE}"
    exit 1
  fi
  echo "${img}"
}

comment_build() {
  sed -i \
    -e 's/^\(\s*\)build:/\1# build:/' \
    -e 's/^\(\s*\)context:/\1# context:/' \
    -e 's/^\(\s*\)dockerfile:/\1# dockerfile:/' \
    "${COMPOSE_FILE}"
}


uncomment_build() {
  # Uncomment build block while keeping indentation
  sed -i \
    -e 's/^\(\s*\)#\s*build:/\1build:/' \
    -e 's/^\(\s*\)#\s*context:/\1  context:/' \
    -e 's/^\(\s*\)#\s*dockerfile:/\1  dockerfile:/' \
    "${COMPOSE_FILE}"
}

###############################################################
# MAIN
###############################################################
require_root
check_docker
ensure_config

log "Project directory: ${SCRIPT_DIR}"
log "Docker directory:  ${DOCKER_DIR}"
log "Compose file:      ${COMPOSE_FILE}"

IMAGE="$(get_image)"
log "Detected image from docker-compose.yml: ${IMAGE}"

echo
read -r -p "Do you want to build the image locally? (y/N): " choice
choice="${choice:-N}"

if [[ "${choice}" =~ ^[yY]$ ]]; then
  log "Local build selected."
  uncomment_build
  (
    cd "${DOCKER_DIR}"
    log "Stopping previous softvpn container if it exists..."
    docker compose down || true

    log "Building image locally (no cache)..."
    DOCKER_BUILDKIT=0 docker compose build --no-cache --progress=plain
  )
else
  log "Using prebuilt image (default)."
  comment_build

  log "Pulling image: ${IMAGE}"
  docker pull "${IMAGE}"
fi

log "Starting softvpn container with docker compose..."
(
  cd "${DOCKER_DIR}"
  docker compose up -d
)

log "Current softvpn container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E '^softvpn' || true

chmod +x "${CHAOSBOX_RUN}"

if [[ -x "${CHAOSBOX_RUN}" ]]; then
  log "Running Chaosbox runtime script: ${CHAOSBOX_RUN}"

  "${CHAOSBOX_RUN}"
else
  log "Chaosbox runtime script not found or not executable: ${CHAOSBOX_RUN}"
  log "If you need Chaosbox features, please ensure this script exists and is executable."
fi

### --------------------------------------------------------
### Ensure required scripts (+x) after first clone
### --------------------------------------------------------
# Detect project root (install.sh所在目录)
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
NEEDED_SCRIPTS=(
  "${PROJECT_DIR}/start.sh"
  "${PROJECT_DIR}/shutdown.sh"
  "${PROJECT_DIR}/uninstall.sh"
  "${PROJECT_DIR}/restart.sh"
)

for SCRIPT in "${NEEDED_SCRIPTS[@]}"; do
  if [[ -f "$SCRIPT" ]]; then
    if [[ ! -x "$SCRIPT" ]]; then
      echo "[install] Adding +x permission to: $(basename "$SCRIPT")"
      chmod +x "$SCRIPT"
    fi
  else
    echo "[install] WARNING: Missing script: $SCRIPT"
  fi
done

cat <<EOF

-----------------------------------------------------
Chaosbox + SoftEther VPN installation completed.
-----------------------------------------------------

- Image used: ${IMAGE}
- Compose file: ${COMPOSE_FILE}
- Config file: ${CONFIG_FILE}

To check VPN logs:
  docker logs softvpn --tail=100

To stop VPN:
  cd ${DOCKER_DIR}
  docker compose down

-----------------------------------------------------
EOF
