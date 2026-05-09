#!/bin/bash
set -euo pipefail

# =============================================================================
# cleanup_daemon.sh — Auto-destroy expired environments
# Runs in background, checks every 60 seconds
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/logs/cleanup.log"

mkdir -p "$PROJECT_ROOT/logs" "$PROJECT_ROOT/envs"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$LOG_FILE"
}

log "Cleanup daemon started (PID: $$)"

while true; do
    for state_file in "$PROJECT_ROOT/envs"/*.json; do
        # Skip if no JSON files exist (glob didn't match)
        [ -f "$state_file" ] || continue

        ENV_ID=$(jq -r '.id' "$state_file" 2>/dev/null) || continue
        CREATED_AT=$(jq -r '.created_at' "$state_file" 2>/dev/null) || continue
        TTL_SECONDS=$(jq -r '.ttl_seconds' "$state_file" 2>/dev/null) || continue

        # Calculate if expired
        CREATED_EPOCH=$(date -d "$CREATED_AT" +%s 2>/dev/null) || continue
        NOW_EPOCH=$(date +%s)
        EXPIRY_EPOCH=$((CREATED_EPOCH + TTL_SECONDS))

        if [ "$NOW_EPOCH" -gt "$EXPIRY_EPOCH" ]; then
            log "Environment $ENV_ID EXPIRED (created: $CREATED_AT, TTL: ${TTL_SECONDS}s). Destroying..."
            if "$SCRIPT_DIR/destroy_env.sh" "$ENV_ID" >> "$LOG_FILE" 2>&1; then
                log "Environment $ENV_ID destroyed successfully"
            else
                log "ERROR: Failed to destroy environment $ENV_ID"
            fi
        fi
    done

    sleep 60
done
