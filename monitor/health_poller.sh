#!/bin/bash
set -euo pipefail

# =============================================================================
# health_poller.sh — Monitor health of all active sandbox environments
# Polls GET /health every 30 seconds, marks degraded after 3 consecutive fails
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

mkdir -p "$PROJECT_ROOT/logs" "$PROJECT_ROOT/envs"

# File to track consecutive failures per env
FAIL_TRACKER="/tmp/sandbox_health_failures"
mkdir -p "$FAIL_TRACKER"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

log "Health poller started (PID: $$)"

while true; do
    for state_file in "$PROJECT_ROOT/envs"/*.json; do
        [ -f "$state_file" ] || continue

        ENV_ID=$(jq -r '.id' "$state_file" 2>/dev/null) || continue
        CONTAINER_NAME=$(jq -r '.container_name' "$state_file" 2>/dev/null) || continue

        LOG_DIR="$PROJECT_ROOT/logs/${ENV_ID}"
        mkdir -p "$LOG_DIR"
        HEALTH_LOG="$LOG_DIR/health.log"

        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Poll health through localhost/Nginx proxy
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" \
            --max-time 5 \
            "http://localhost/env/${ENV_ID}/health" 2>/dev/null) || RESPONSE="000 0.000"

        HTTP_CODE=$(echo "$RESPONSE" | awk '{print $1}')
        LATENCY=$(echo "$RESPONSE" | awk '{print $2}')

        echo "${TIMESTAMP} ${HTTP_CODE} ${LATENCY}s" >> "$HEALTH_LOG"

        # Track consecutive failures
        FAIL_FILE="$FAIL_TRACKER/${ENV_ID}"

        if [ "$HTTP_CODE" != "200" ]; then
            CURRENT_FAILS=0
            [ -f "$FAIL_FILE" ] && CURRENT_FAILS=$(cat "$FAIL_FILE")
            CURRENT_FAILS=$((CURRENT_FAILS + 1))
            echo "$CURRENT_FAILS" > "$FAIL_FILE"

            if [ "$CURRENT_FAILS" -ge 3 ]; then
                log "WARNING: Environment $ENV_ID is DEGRADED ($CURRENT_FAILS consecutive failures)"
                # Update state file atomically
                if [ -f "$state_file" ]; then
                    jq '.status = "degraded"' "$state_file" > "${state_file}.tmp" \
                        && mv "${state_file}.tmp" "$state_file"
                fi
            fi
        else
            # Reset failure count on success
            echo "0" > "$FAIL_FILE"
        fi
    done

    sleep 30
done
