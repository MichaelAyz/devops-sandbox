"""
DevOps Sandbox — Control API
Lightweight FastAPI wrapper around platform shell scripts.
"""

import subprocess
import json
import os
import glob
import time
from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(
    title="DevOps Sandbox API",
    description="Self-service platform for spinning up isolated temporary environments",
    version="1.0.0",
)

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATFORM_DIR = os.path.join(PROJECT_ROOT, "platform")
ENVS_DIR = os.path.join(PROJECT_ROOT, "envs")
LOGS_DIR = os.path.join(PROJECT_ROOT, "logs")


# --- Request/Response Models ---

class CreateEnvRequest(BaseModel):
    name: str
    ttl: Optional[int] = 30


class OutageRequest(BaseModel):
    mode: str


# --- Helper Functions ---

def run_script(script: str, args: list) -> dict:
    """Run a platform shell script and return its output."""
    cmd = ["bash", os.path.join(PLATFORM_DIR, script)] + [str(a) for a in args]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_ROOT)
    return {
        "stdout": result.stdout,
        "stderr": result.stderr,
        "returncode": result.returncode,
    }


def read_state_file(env_id: str) -> dict:
    """Read an environment's state file."""
    path = os.path.join(ENVS_DIR, f"{env_id}.json")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail=f"Environment not found: {env_id}")
    with open(path, "r") as f:
        return json.load(f)


def get_all_envs() -> list:
    """Read all environment state files."""
    envs = []
    pattern = os.path.join(ENVS_DIR, "*.json")
    for path in glob.glob(pattern):
        try:
            with open(path, "r") as f:
                env = json.load(f)
            # Calculate TTL remaining
            created = datetime.strptime(env["created_at"], "%Y-%m-%dT%H:%M:%SZ")
            created = created.replace(tzinfo=timezone.utc)
            elapsed = (datetime.now(timezone.utc) - created).total_seconds()
            env["ttl_remaining_seconds"] = max(0, int(env["ttl_seconds"] - elapsed))
            envs.append(env)
        except (json.JSONDecodeError, KeyError):
            continue
    return envs


# --- API Endpoints ---

@app.post("/envs", summary="Create a new environment")
def create_env(req: CreateEnvRequest):
    result = run_script("create_env.sh", [req.name, req.ttl])
    if result["returncode"] != 0:
        raise HTTPException(status_code=500, detail=result["stderr"])
    # Find the newly created env by parsing output for the ID line
    env_id = None
    for line in result["stdout"].split("\n"):
        if "ID:" in line and "env-" in line:
            env_id = line.split("ID:")[-1].strip()
            break
    response = {"message": "Environment created", "output": result["stdout"]}
    if env_id:
        try:
            state = read_state_file(env_id)
            response["environment"] = state
        except HTTPException:
            pass
    return response


@app.get("/envs", summary="List all active environments")
def list_envs():
    return {"environments": get_all_envs(), "count": len(get_all_envs())}


@app.delete("/envs/{env_id}", summary="Destroy an environment")
def destroy_env(env_id: str):
    # Verify env exists
    read_state_file(env_id)
    result = run_script("destroy_env.sh", [env_id])
    if result["returncode"] != 0:
        raise HTTPException(status_code=500, detail=result["stderr"])
    return {"message": f"Environment {env_id} destroyed", "output": result["stdout"]}


@app.get("/envs/{env_id}/logs", summary="Get last 100 lines of app logs")
def get_env_logs(env_id: str):
    # Check env exists or was archived
    log_path = os.path.join(LOGS_DIR, env_id, "app.log")
    archived_path = os.path.join(LOGS_DIR, "archived", env_id, "app.log")

    target = None
    if os.path.exists(log_path):
        target = log_path
    elif os.path.exists(archived_path):
        target = archived_path
    else:
        raise HTTPException(status_code=404, detail=f"No logs found for env: {env_id}")

    with open(target, "r") as f:
        lines = f.readlines()
    return {"env_id": env_id, "lines": len(lines), "logs": lines[-100:]}


@app.get("/envs/{env_id}/health", summary="Get last 10 health check results")
def get_env_health(env_id: str):
    health_path = os.path.join(LOGS_DIR, env_id, "health.log")
    archived_path = os.path.join(LOGS_DIR, "archived", env_id, "health.log")

    target = None
    if os.path.exists(health_path):
        target = health_path
    elif os.path.exists(archived_path):
        target = archived_path
    else:
        raise HTTPException(
            status_code=404, detail=f"No health data found for env: {env_id}"
        )

    with open(target, "r") as f:
        lines = f.readlines()

    # Parse health log entries
    results = []
    for line in lines[-10:]:
        parts = line.strip().split()
        if len(parts) >= 3:
            results.append(
                {"timestamp": parts[0], "status_code": parts[1], "latency": parts[2]}
            )

    return {"env_id": env_id, "health_checks": results}


@app.post("/envs/{env_id}/outage", summary="Trigger outage simulation")
def trigger_outage(env_id: str, req: OutageRequest):
    # Verify env exists
    read_state_file(env_id)
    valid_modes = ["crash", "pause", "network", "recover", "stress"]
    if req.mode not in valid_modes:
        raise HTTPException(
            status_code=400, detail=f"Invalid mode. Valid: {valid_modes}"
        )
    result = run_script("simulate_outage.sh", ["--env", env_id, "--mode", req.mode])
    if result["returncode"] != 0:
        raise HTTPException(status_code=500, detail=result["stderr"])
    return {
        "message": f"Outage simulation ({req.mode}) triggered on {env_id}",
        "output": result["stdout"],
    }


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("API_PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
