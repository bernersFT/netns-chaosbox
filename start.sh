#!/bin/bash
set -e

### --------------------------------------------------------
###  Start Script for Chaosbox
### --------------------------------------------------------

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCKER_DIR="${PROJECT_DIR}/docker"
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"
CHAOSBOX_RUN="${PROJECT_DIR}/chaosbox/latest/run_chaosbox.sh"

log() {
  echo "[start] $1"
}

### --------------------------------------------------------
### 1. Check compose file exists
### --------------------------------------------------------
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  log "ERROR: Compose file not found: ${COMPOSE_FILE}"
  exit 1
fi

### --------------------------------------------------------
### 2. Start docker compose
### --------------------------------------------------------
log "Starting SoftVPN container using docker-compose..."
docker compose -f "${COMPOSE_FILE}" up -d

log "Docker compose started. Current container state:"
docker ps | grep softvpn || log "WARNING: softvpn container not found!"

### --------------------------------------------------------
### 3. Run Chaosbox runtime script
### --------------------------------------------------------
if [[ ! -f "${CHAOSBOX_RUN}" ]]; then
  log "ERROR: Missing runtime script: ${CHAOSBOX_RUN}"
  exit 1
fi

log "Ensuring +x permission for Chaosbox runtime script..."
chmod +x "${CHAOSBOX_RUN}"

log "Executing Chaosbox runtime script..."
"${CHAOSBOX_RUN}"

log "Start completed successfully."
