#!/bin/bash
# shutdown.sh - Stop Chaosbox SoftVPN container and rollback host networking.

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$BASE_DIR/docker/docker-compose.yml"
ROLLBACK_SH="$BASE_DIR/chaosbox/utils/rollback.sh"

log() {
  echo "[shutdown] $*"
}

log "Base directory: $BASE_DIR"
log "Compose file:   $COMPOSE_FILE"
log "Rollback script: $ROLLBACK_SH"

# 1) Stop containers via docker compose
if [[ -f "$COMPOSE_FILE" ]]; then
  log "Stopping SoftVPN containers (docker compose down)..."
  docker compose -f "$COMPOSE_FILE" down || log "WARNING: docker compose down failed or nothing to stop."
else
  log "WARNING: docker-compose file not found: $COMPOSE_FILE"
fi

# 2) Run rollback.sh to restore host networking
if [[ -f "$ROLLBACK_SH" ]]; then
  log "Ensuring rollback.sh is executable..."
  chmod +x "$ROLLBACK_SH"

  log "Running rollback.sh..."
  "$ROLLBACK_SH"
else
  log "WARNING: rollback.sh not found at: $ROLLBACK_SH"
fi

log "Shutdown procedure completed."
