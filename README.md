# DevOps Sandbox Platform

A self-service platform for spinning up isolated, short-lived Docker environments with dynamic routing, health monitoring, outage simulation, and automatic cleanup.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Linux VM (Host)                           │
│                                                                  │
│  ┌───────────┐   ┌──────────────┐   ┌───────────────────────┐   │
│  │ Makefile   │──▶│  Control API │──▶│  Platform Scripts      │   │
│  │ (CLI)      │   │  (FastAPI)   │   │  create / destroy /    │   │
│  └───────────┘   │  :8000       │   │  cleanup / simulate    │   │
│                   └──────┬───────┘   └──────────┬────────────┘   │
│                          │                      │                │
│                          ▼                      ▼                │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │                    Docker Engine                           │   │
│  │                                                            │   │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────┐              │   │
│  │  │  Nginx   │   │  Env-A   │   │  Env-B   │   ...        │   │
│  │  │  :80     │   │  (Flask) │   │  (Flask) │              │   │
│  │  └────┬─────┘   └────┬─────┘   └────┬─────┘              │   │
│  │       │               │               │                    │   │
│  │  nginx-net ◀──────────┼───────────────┘                    │   │
│  │               sandbox-env-A    sandbox-env-B               │   │
│  │              (isolated net)   (isolated net)               │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌────────────────┐   ┌────────────────┐   ┌─────────────┐      │
│  │ Cleanup Daemon  │   │ Health Monitor  │   │ State/Logs  │      │
│  │ (60s loop)      │   │ (30s poll)      │   │ envs/*.json │      │
│  └────────────────┘   └────────────────┘   │ logs/*/     │      │
│                                             └─────────────┘      │
└──────────────────────────────────────────────────────────────────┘
```

### Networking Approach

Each sandbox environment gets its own **isolated Docker network** (`sandbox-{ENV_ID}`). The Nginx container is connected to **every** active environment's network, enabling it to reverse-proxy traffic to each app container. Environments are completely isolated from each other — they can only be reached through Nginx.

When an environment is destroyed, Nginx is disconnected from that network before the network is removed.

## Prerequisites

- **Docker** (with Docker Engine running)
- **Python 3.8+** with pip
- **jq** (JSON processor)
- **curl**
- **xxd** (usually included with vim)
- **make**

### Install on Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y docker.io python3 python3-pip python3-venv jq curl make
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# Log out and back in for Docker group to take effect
```

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/<your-username>/devops-sandbox.git
cd devops-sandbox

# 2. Copy environment config
cp .env.example .env

# 3. Start the platform
make up

# 4. Create your first environment
make create
# Enter a name (e.g., "my-app") and TTL (e.g., 5 for 5 minutes)

# 5. Access it
curl http://yzbtboy.duckdns.org/env/<ENV_ID>/
```

## Full Demo Walkthrough

### 1. Start the Platform

```bash
make up
```

This builds the demo app Docker image, starts Nginx, the cleanup daemon, health monitor, and the API server.

### 2. Create an Environment

```bash
make create
# Name: demo-app
# TTL: 5
```

Note the `ENV_ID` from the output (e.g., `env-1715270400-a1b2c3d4`).

### 3. Verify It's Running

```bash
# Access the app through Nginx
curl http://yzbtboy.duckdns.org/env/<ENV_ID>/

# Check health
curl http://yzbtboy.duckdns.org/env/<ENV_ID>/health
```

### 4. Check Health Status

```bash
make health
```

### 5. Simulate an Outage (Crash)

```bash
make simulate ENV=<ENV_ID> MODE=crash
```

Wait ~90 seconds. The health monitor will detect the failure and mark the environment as `degraded`.

```bash
make health
# Status should show "degraded"
```

### 6. Recover

```bash
make simulate ENV=<ENV_ID> MODE=recover
```

### 7. View Logs

```bash
make logs ENV=<ENV_ID>
```

### 8. Wait for Auto-Destroy

With a 5-minute TTL, the cleanup daemon will automatically destroy the environment after 5 minutes. Check `logs/cleanup.log` to confirm.

### 9. Shut Everything Down

```bash
make down
```

## API Reference

The API runs on port 8000 with auto-generated docs at `http://yzbtboy.duckdns.org:8000/docs`.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/envs` | Create a new environment. Body: `{"name": "...", "ttl": 30}` |
| `GET` | `/envs` | List all active environments with TTL remaining |
| `DELETE` | `/envs/{id}` | Destroy a specific environment |
| `GET` | `/envs/{id}/logs` | Get last 100 lines of app logs |
| `GET` | `/envs/{id}/health` | Get last 10 health check results |
| `POST` | `/envs/{id}/outage` | Trigger outage simulation. Body: `{"mode": "crash"}` |

### Example API Calls

```bash
# Create environment
curl -X POST http://yzbtboy.duckdns.org:8000/envs \
  -H "Content-Type: application/json" \
  -d '{"name": "test-app", "ttl": 10}'

# List environments
curl http://yzbtboy.duckdns.org:8000/envs

# Simulate outage
curl -X POST http://yzbtboy.duckdns.org:8000/envs/<ENV_ID>/outage \
  -H "Content-Type: application/json" \
  -d '{"mode": "pause"}'

# Destroy environment
curl -X DELETE http://yzbtboy.duckdns.org:8000/envs/<ENV_ID>
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make up` | Start Nginx, cleanup daemon, health monitor, and API |
| `make down` | Stop everything and destroy all environments |
| `make create` | Create a new environment (interactive prompts) |
| `make destroy ENV=...` | Destroy a specific environment |
| `make logs ENV=...` | Tail logs for an environment |
| `make health` | Show health status of all environments |
| `make simulate ENV=... MODE=...` | Run outage simulation |
| `make clean` | Wipe all state, logs, and archives |

## Project Structure

```
devops-sandbox/
├── app/                  # Demo application deployed in each environment
│   ├── app.py            # Flask app with / and /health endpoints
│   ├── Dockerfile
│   └── requirements.txt
├── platform/             # Core platform scripts and API
│   ├── create_env.sh     # Create isolated environment
│   ├── destroy_env.sh    # Tear down environment
│   ├── cleanup_daemon.sh # Auto-destroy expired environments
│   ├── simulate_outage.sh # Chaos engineering simulation
│   ├── api.py            # FastAPI control API
│   └── requirements.txt
├── nginx/                # Reverse proxy configuration
│   ├── nginx.conf        # Main Nginx config
│   └── conf.d/           # Auto-generated per-environment configs
├── monitor/              # Health monitoring
│   └── health_poller.sh  # Polls /health every 30s
├── logs/                 # Runtime logs (gitignored)
├── envs/                 # Environment state files (gitignored)
├── Makefile              # All platform operations
├── .env.example          # Configuration template
├── .gitignore
└── README.md
```

