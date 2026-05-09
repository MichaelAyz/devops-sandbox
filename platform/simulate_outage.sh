#!/bin/bash
set -euo pipefail

# =============================================================================
# simulate_outage.sh — Chaos engineering for sandbox environments
# Usage: simulate_outage.sh --env <env_id> --mode <crash|pause|network|recover|stress>
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Parse arguments ---
ENV_ID=""
MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)  ENV_ID="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        *) echo "[-] Unknown argument: $1"; exit 1 ;;
    esac
done

if [ -z "$ENV_ID" ] || [ -z "$MODE" ]; then
    echo "Usage: simulate_outage.sh --env <env_id> --mode <crash|pause|network|recover|stress>"
    exit 1
fi

# --- GUARD: Never operate on infrastructure containers ---
PROTECTED=("sandbox-nginx" "sandbox-api" "sandbox-daemon" "sandbox-monitor")
CONTAINER_NAME=$(docker ps -a --filter "label=sandbox.env=${ENV_ID}" --format '{{.Names}}' | head -1)

if [ -z "$CONTAINER_NAME" ]; then
    echo "[-] No container found for env: $ENV_ID"
    exit 1
fi

for p in "${PROTECTED[@]}"; do
    if [ "$CONTAINER_NAME" = "$p" ]; then
        echo "[-] REFUSED: Cannot simulate outage on infrastructure container: $CONTAINER_NAME"
        exit 1
    fi
done

STATE_FILE="$PROJECT_ROOT/envs/${ENV_ID}.json"
NETWORK_NAME="sandbox-${ENV_ID}"

echo "[*] Outage simulation: mode=$MODE | env=$ENV_ID | container=$CONTAINER_NAME"

# --- Helper to update state atomically ---
update_status() {
    local new_status="$1"
    if [ -f "$STATE_FILE" ]; then
        jq --arg s "$new_status" '.status = $s' "$STATE_FILE" > "${STATE_FILE}.tmp" \
            && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}

case "$MODE" in
    crash)
        docker kill "$CONTAINER_NAME"
        update_status "crashed"
        echo "[+] Container KILLED (crash mode). Health monitor should detect within 90s."
        ;;
    pause)
        docker pause "$CONTAINER_NAME"
        update_status "paused"
        echo "[+] Container PAUSED. Use --mode recover to unpause."
        ;;
    network)
        docker network disconnect "$NETWORK_NAME" "$CONTAINER_NAME"
        update_status "network_isolated"
        echo "[+] Container DISCONNECTED from network. Use --mode recover to reconnect."
        ;;
    recover)
        CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
        echo "[*] Current container status: $CONTAINER_STATUS"

        case "$CONTAINER_STATUS" in
            paused)
                docker unpause "$CONTAINER_NAME"
                echo "[+] Container UNPAUSED"
                ;;
            exited|created)
                docker start "$CONTAINER_NAME"
                # Reconnect to network in case it was disconnected
                docker network connect "$NETWORK_NAME" "$CONTAINER_NAME" 2>/dev/null || true
                echo "[+] Container RESTARTED"
                ;;
            running)
                # Likely network-disconnected — reconnect
                docker network connect "$NETWORK_NAME" "$CONTAINER_NAME" 2>/dev/null || true
                echo "[+] Container RECONNECTED to network"
                ;;
            *)
                echo "[-] Cannot recover from status: $CONTAINER_STATUS"
                exit 1
                ;;
        esac
        update_status "running"
        ;;
    stress)
        echo "[*] Starting CPU stress test (30 seconds)..."
        docker exec "$CONTAINER_NAME" stress-ng --cpu 2 --timeout 30s &
        echo "[+] Stress test running in background (30s)"
        ;;
    *)
        echo "[-] Unknown mode: $MODE"
        echo "    Valid modes: crash, pause, network, recover, stress"
        exit 1
        ;;
esac
