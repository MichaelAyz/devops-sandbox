.PHONY: up down create destroy logs health simulate clean

# =============================================================================
# DevOps Sandbox Platform — Makefile
# =============================================================================

PROJECT_ROOT := $(shell pwd)

# --- Start the entire platform ---
up:
	@echo "=== Starting DevOps Sandbox Platform ==="
	@mkdir -p logs envs nginx/conf.d
	@# Build the demo app image
	docker build -t sandbox-app:latest ./app/
	@# Create the nginx network
	docker network create sandbox-nginx-net 2>/dev/null || true
	@# Start Nginx container
	@if ! docker ps --format '{{.Names}}' | grep -q '^sandbox-nginx$$'; then \
		docker run -d \
			--name sandbox-nginx \
			--network sandbox-nginx-net \
			-p 80:80 \
			-v $(PROJECT_ROOT)/nginx/nginx.conf:/etc/nginx/nginx.conf \
			-v $(PROJECT_ROOT)/nginx/conf.d:/etc/nginx/conf.d \
			nginx:alpine; \
		echo "[+] Nginx started on port 80"; \
	else \
		echo "[*] Nginx already running"; \
	fi
	@# Install API dependencies
	pip3 install -q -r platform/requirements.txt
	@# Start cleanup daemon
	@if [ ! -f .cleanup_daemon.pid ] || ! kill -0 $$(cat .cleanup_daemon.pid 2>/dev/null) 2>/dev/null; then \
		nohup bash platform/cleanup_daemon.sh > /dev/null 2>&1 & \
		echo $$! > .cleanup_daemon.pid; \
		echo "[+] Cleanup daemon started (PID: $$(cat .cleanup_daemon.pid))"; \
	else \
		echo "[*] Cleanup daemon already running"; \
	fi
	@# Start health monitor
	@if [ ! -f .health_monitor.pid ] || ! kill -0 $$(cat .health_monitor.pid 2>/dev/null) 2>/dev/null; then \
		nohup bash monitor/health_poller.sh > logs/health_monitor.log 2>&1 & \
		echo $$! > .health_monitor.pid; \
		echo "[+] Health monitor started (PID: $$(cat .health_monitor.pid))"; \
	else \
		echo "[*] Health monitor already running"; \
	fi
	@# Start API server
	@if [ ! -f .api.pid ] || ! kill -0 $$(cat .api.pid 2>/dev/null) 2>/dev/null; then \
		nohup python3 platform/api.py > logs/api.log 2>&1 & \
		echo $$! > .api.pid; \
		echo "[+] API server started (PID: $$(cat .api.pid))"; \
	else \
		echo "[*] API server already running"; \
	fi
	@echo ""
	@echo "=== Platform is UP ==="
	@echo "  Nginx:  http://yzbtboy.duckdns.org/"
	@echo "  API:    http://yzbtboy.duckdns.org:8000/docs"
	@echo ""

# --- Stop everything and destroy all envs ---
down:
	@echo "=== Shutting down DevOps Sandbox Platform ==="
	@# Destroy all active environments
	@for f in envs/*.json; do \
		if [ -f "$$f" ]; then \
			ENV_ID=$$(jq -r '.id' "$$f" 2>/dev/null); \
			if [ -n "$$ENV_ID" ] && [ "$$ENV_ID" != "null" ]; then \
				echo "[*] Destroying env: $$ENV_ID"; \
				bash platform/destroy_env.sh "$$ENV_ID" 2>/dev/null || true; \
			fi; \
		fi; \
	done
	@# Stop background processes
	@if [ -f .cleanup_daemon.pid ]; then kill $$(cat .cleanup_daemon.pid) 2>/dev/null || true; rm -f .cleanup_daemon.pid; fi
	@if [ -f .health_monitor.pid ]; then kill $$(cat .health_monitor.pid) 2>/dev/null || true; rm -f .health_monitor.pid; fi
	@if [ -f .api.pid ]; then kill $$(cat .api.pid) 2>/dev/null || true; rm -f .api.pid; fi
	@# Stop and remove Nginx container
	docker rm -f sandbox-nginx 2>/dev/null || true
	@# Remove nginx network
	docker network rm sandbox-nginx-net 2>/dev/null || true
	@echo "=== Platform is DOWN ==="

# --- Create a new environment ---
create:
	@read -p "Environment name: " NAME; \
	read -p "TTL in minutes (default 30): " TTL; \
	TTL=$${TTL:-30}; \
	bash platform/create_env.sh "$$NAME" "$$TTL"

# --- Destroy a specific environment ---
destroy:
	@if [ -z "$(ENV)" ]; then echo "Usage: make destroy ENV=<env_id>"; exit 1; fi
	bash platform/destroy_env.sh $(ENV)

# --- Tail logs for an environment ---
logs:
	@if [ -z "$(ENV)" ]; then echo "Usage: make logs ENV=<env_id>"; exit 1; fi
	@if [ -f "logs/$(ENV)/app.log" ]; then \
		tail -f logs/$(ENV)/app.log; \
	elif [ -f "logs/archived/$(ENV)/app.log" ]; then \
		echo "(archived logs)"; \
		tail -100 logs/archived/$(ENV)/app.log; \
	else \
		echo "No logs found for env: $(ENV)"; \
	fi

# --- Show health status of all environments ---
health:
	@echo "=== Environment Health Status ==="
	@for f in envs/*.json; do \
		if [ -f "$$f" ]; then \
			ENV_ID=$$(jq -r '.id' "$$f"); \
			NAME=$$(jq -r '.name' "$$f"); \
			STATUS=$$(jq -r '.status' "$$f"); \
			TTL=$$(jq -r '.ttl_seconds' "$$f"); \
			CREATED=$$(jq -r '.created_at' "$$f"); \
			echo "  $$ENV_ID ($$NAME) — status: $$STATUS | TTL: $${TTL}s | created: $$CREATED"; \
			if [ -f "logs/$$ENV_ID/health.log" ]; then \
				echo "    Last 3 health checks:"; \
				tail -3 "logs/$$ENV_ID/health.log" | sed 's/^/      /'; \
			fi; \
			echo ""; \
		fi; \
	done
	@if [ ! -f envs/*.json ] 2>/dev/null; then echo "  No active environments."; fi

# --- Run outage simulation ---
simulate:
	@if [ -z "$(ENV)" ] || [ -z "$(MODE)" ]; then echo "Usage: make simulate ENV=<env_id> MODE=<crash|pause|network|recover|stress>"; exit 1; fi
	bash platform/simulate_outage.sh --env $(ENV) --mode $(MODE)

# --- Wipe all state, logs, and archives ---
clean:
	@echo "=== Cleaning all state ==="
	rm -rf logs/* envs/* nginx/conf.d/*.conf
	rm -f .cleanup_daemon.pid .health_monitor.pid .api.pid
	rm -rf /tmp/sandbox_health_failures
	@echo "=== Clean complete ==="
