#!/bin/bash
# uninstall.sh - Completely uninstall Chaosbox SoftVPN:
#   - Stop and remove containers / networks / volumes
#   - Remove netns-chaosbox images
#   - Rollback host networking via rollback.sh

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$BASE_DIR/docker/docker-compose.yml"
ROLLBACK_SH="$BASE_DIR/chaosbox/utils/rollback.sh"

IMAGE_REPO_PREFIX="ghcr.io/bernersft/netns-chaosbox"
LOCAL_IMAGE_NAME="netns-chaosbox"

log() {
  echo "[uninstall] $*"
}

log "Base directory: $BASE_DIR"
log "Compose file:   $COMPOSE_FILE"
log "Rollback script: $ROLLBACK_SH"

# 1) docker compose down + remove resources
if [[ -f "$COMPOSE_FILE" ]]; then
  log "Stopping and removing SoftVPN stack (docker compose down --rmi all --volumes --remove-orphans)..."
  docker compose -f "$COMPOSE_FILE" down --rmi all --volumes --remove-orphans || \
    log "WARNING: docker compose down returned non-zero (maybe nothing to remove)."
else
  log "WARNING: docker-compose file not found: $COMPOSE_FILE"
fi

# 2) Remove images related to netns-chaosbox
log "Removing Docker images related to netns-chaosbox (if any)..."

set +e  # 删除不存在的镜像时不要让脚本直接退出

# GHCR images (any tag)
docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^${IMAGE_REPO_PREFIX}:" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^${IMAGE_REPO_PREFIX}:" | while read -r img; do
    log "Removing image: $img"
    docker rmi "$img" || log "WARNING: Failed to remove image $img"
  done
else
  log "No GHCR images found for prefix: ${IMAGE_REPO_PREFIX}"
fi

# Local images named netns-chaosbox (if any)
docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^${LOCAL_IMAGE_NAME}:" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^${LOCAL_IMAGE_NAME}:" | while read -r img; do
    log "Removing local image: $img"
    docker rmi "$img" || log "WARNING: Failed to remove local image $img"
  done
else
  log "No local images found with name: ${LOCAL_IMAGE_NAME}"
fi

set -e

# 3) Run rollback.sh to restore host networking
if [[ -f "$ROLLBACK_SH" ]]; then
  log "Ensuring rollback.sh is executable..."
  chmod +x "$ROLLBACK_SH"

  log "Running rollback.sh..."
  "$ROLLBACK_SH"
else
  log "WARNING: rollback.sh not found at: $ROLLBACK_SH"
fi

log "Uninstall procedure completed. Docker state should be close to pre-install."
