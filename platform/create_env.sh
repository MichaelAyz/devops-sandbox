#!/bin/bash
set -euo pipefail

# =============================================================================
# create_env.sh — Create a new isolated sandbox environment
# Usage: create_env.sh <name> [ttl_minutes]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source configuration
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

DOMAIN="${DOMAIN:-localhost}"
NGINX_CONTAINER="sandbox-nginx"
APP_IMAGE="sandbox-app:latest"

# --- Input validation ---
ENV_NAME="${1:?Usage: create_env.sh <name> [ttl_minutes]}"
TTL_MINUTES="${2:-${DEFAULT_TTL:-30}}"

# --- Generate unique ENV ID ---
TIMESTAMP=$(date +%s)
RANDOM_HEX=$(head -c 4 /dev/urandom | xxd -p)
ENV_ID="env-${TIMESTAMP}-${RANDOM_HEX}"

# --- Derived names ---
NETWORK_NAME="sandbox-${ENV_ID}"
CONTAINER_NAME="sandbox-app-${ENV_ID}"
ENV_DIR="$PROJECT_ROOT/envs"
LOG_DIR="$PROJECT_ROOT/logs/${ENV_ID}"
NGINX_CONF_DIR="$PROJECT_ROOT/nginx/conf.d"

# --- Create directories ---
mkdir -p "$ENV_DIR" "$LOG_DIR" "$NGINX_CONF_DIR"

echo "[+] Creating environment: $ENV_ID (name: $ENV_NAME, TTL: ${TTL_MINUTES}m)"

# --- Create dedicated Docker network ---
docker network create "$NETWORK_NAME" > /dev/null 2>&1
echo "[+] Created network: $NETWORK_NAME"

# --- Build app image if not present ---
if ! docker image inspect "$APP_IMAGE" > /dev/null 2>&1; then
    echo "[*] Building app image..."
    docker build -t "$APP_IMAGE" "$PROJECT_ROOT/app/"
fi

# --- Start app container ---
docker run -d \
    --name "$CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    --label "sandbox.env=${ENV_ID}" \
    -e "ENV_ID=${ENV_ID}" \
    "$APP_IMAGE" > /dev/null
echo "[+] Started container: $CONTAINER_NAME"

# --- Connect Nginx container to this env's network ---
docker network connect "$NETWORK_NAME" "$NGINX_CONTAINER" 2>/dev/null || true
echo "[+] Connected Nginx to network: $NETWORK_NAME"

# --- Write Nginx config ---
cat > "${NGINX_CONF_DIR}/${ENV_ID}.conf" <<NGINXEOF
# Auto-generated config for environment: ${ENV_ID}
location /env/${ENV_ID}/ {
    proxy_pass http://${CONTAINER_NAME}:5000/;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_connect_timeout 5s;
    proxy_read_timeout 30s;
}
NGINXEOF
echo "[+] Wrote Nginx config: nginx/conf.d/${ENV_ID}.conf"

# --- Reload Nginx ---
docker exec "$NGINX_CONTAINER" nginx -s reload
echo "[+] Nginx reloaded"

# --- Start log shipping (Approach A) ---
CONTAINER_ID=$(docker inspect --format='{{.Id}}' "$CONTAINER_NAME")
docker logs -f "$CONTAINER_ID" >> "$LOG_DIR/app.log" 2>&1 &
LOG_PID=$!
echo "[+] Log shipping started (PID: $LOG_PID)"

# --- Write state file ATOMICALLY (tmp + mv) ---
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TTL_SECONDS=$((TTL_MINUTES * 60))

cat > "${ENV_DIR}/${ENV_ID}.json.tmp" <<EOF
{
    "id": "${ENV_ID}",
    "name": "${ENV_NAME}",
    "container_name": "${CONTAINER_NAME}",
    "container_id": "${CONTAINER_ID}",
    "network": "${NETWORK_NAME}",
    "created_at": "${CREATED_AT}",
    "ttl_seconds": ${TTL_SECONDS},
    "status": "running",
    "log_pid": ${LOG_PID}
}
EOF
mv "${ENV_DIR}/${ENV_ID}.json.tmp" "${ENV_DIR}/${ENV_ID}.json"
echo "[+] State file written: envs/${ENV_ID}.json"

# --- Print summary ---
echo ""
echo "=========================================="
echo "  Environment Created Successfully!"
echo "=========================================="
echo "  ID:      $ENV_ID"
echo "  Name:    $ENV_NAME"
echo "  URL:     http://${DOMAIN}/env/${ENV_ID}/"
echo "  TTL:     ${TTL_MINUTES} minutes"
echo "  Status:  running"
echo "=========================================="
