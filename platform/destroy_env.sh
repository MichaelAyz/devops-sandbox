#!/bin/bash
set -euo pipefail

# =============================================================================
# destroy_env.sh — Destroy an existing sandbox environment
# Usage: destroy_env.sh <env_id>
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NGINX_CONTAINER="sandbox-nginx"

ENV_ID="${1:?Usage: destroy_env.sh <env_id>}"
STATE_FILE="$PROJECT_ROOT/envs/${ENV_ID}.json"

if [ ! -f "$STATE_FILE" ]; then
    echo "[-] State file not found for env: $ENV_ID"
    exit 1
fi

echo "[*] Destroying environment: $ENV_ID"

# --- Read state ---
CONTAINER_NAME=$(jq -r '.container_name' "$STATE_FILE")
NETWORK_NAME=$(jq -r '.network' "$STATE_FILE")
LOG_PID=$(jq -r '.log_pid' "$STATE_FILE")

# --- Kill log-shipping process (prevent zombie) ---
if [ -n "$LOG_PID" ] && [ "$LOG_PID" != "null" ]; then
    kill "$LOG_PID" 2>/dev/null || true
    echo "[+] Killed log shipping process (PID: $LOG_PID)"
fi

# --- Stop and remove all containers with this env's label ---
CONTAINERS=$(docker ps -a --filter "label=sandbox.env=${ENV_ID}" -q)
if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS" | xargs docker rm -f > /dev/null 2>&1
    echo "[+] Removed containers for env $ENV_ID"
fi

# --- Disconnect Nginx from env network, then remove network ---
docker network disconnect "$NETWORK_NAME" "$NGINX_CONTAINER" 2>/dev/null || true
docker network rm "$NETWORK_NAME" 2>/dev/null || true
echo "[+] Removed network: $NETWORK_NAME"

# --- Delete Nginx config and reload ---
rm -f "$PROJECT_ROOT/nginx/conf.d/${ENV_ID}.conf"
docker exec "$NGINX_CONTAINER" nginx -s reload 2>/dev/null || true
echo "[+] Removed Nginx config and reloaded"

# --- Archive logs ---
if [ -d "$PROJECT_ROOT/logs/${ENV_ID}" ]; then
    mkdir -p "$PROJECT_ROOT/logs/archived"
    mv "$PROJECT_ROOT/logs/${ENV_ID}" "$PROJECT_ROOT/logs/archived/${ENV_ID}"
    echo "[+] Archived logs to logs/archived/${ENV_ID}/"
fi

# --- Delete state file ---
rm -f "$STATE_FILE"
echo "[+] Deleted state file"

echo "[*] Environment $ENV_ID destroyed successfully"
