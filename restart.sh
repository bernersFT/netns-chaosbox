#!/bin/bash
# restart.sh.

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SHUTDOWN_SH="$BASE_DIR/shutdown.sh"
START_SH="$BASE_DIR/start.sh"

log() {
  echo "[restarting] $*"
}

log "Base directory: $BASE_DIR"
log "Compose file:   $SHUTDOWN_SH"
log "Rollback script: $START_SH"

# 1) Run shutdown.sh to shutdown docker and chaosbox module.
if [[ -f "$SHUTDOWN_SH" ]]; then
  log "shutdown docker and chaosbox..."
  chmod +x "$SHUTDOWN_SH"

  log "Running shutdown.sh..."
  "$SHUTDOWN_SH"
else
  log "WARNING: rollback.sh not found at: $SHUTDOWN_SH"
fi

# 2) Run start.sh to restore docker and chaosbox
if [[ -f "$START_SH" ]]; then
  log "Ensuring rollback.sh is executable..."
  chmod +x "$START_SH"

  log "Running rollback.sh..."
  "$START_SH"
else
  log "WARNING: rollback.sh not found at: $START_SH"
fi

log "Shutdown procedure completed."