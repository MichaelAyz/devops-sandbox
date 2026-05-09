@channel
DEVOPS TRACK — Stage 5 Task: DevOps Sandbox Platform

Hi Cool Keeds!


You’re building a self-service platform where users can spin up isolated temporary environments, deploy apps into them, simulate outages, monitor health, and destroy everything - automatically or on demand. Think of it as a miniature internal Heroku with a chaos engineering toggle. Every environment is short-lived by design.

Stack: Docker, Docker Compose, Nginx, Bash/Makefile, Python 3. Prometheus + Grafana and GitHub Actions CI are optional extras. Everything must run on a single Linux VM. If a reviewer can’t spin it up with one command, it doesn’t count.

Repo Structure
Name your repo devops-sandbox and structure it like this:

devops-sandbox/
├── platform/          # create_env.sh, destroy_env.sh, cleanup_daemon.sh, api.py|js
├── nginx/             # nginx.conf + conf.d/ (auto-generated per-env configs)
├── monitor/           # health poller
├── logs/              # gitignored
├── envs/              # runtime state files, gitignored
├── Makefile
└── README.md


All secrets go in a .env file, never committed.

What You Must Build

Environment Lifecycle
create_env.sh takes a name and optional TTL (default 30 min). It must: generate a unique env ID, create a dedicated Docker network, start the app container with a sandbox.env=$ENV\_ID label, write a state file to envs/$ENV_ID.json (ID, name, created_at, TTL, status), and register an Nginx route. Print the env URL and TTL on completion.
destroy_env.sh takes an env ID and must: stop and remove all labeled containers, remove the Docker network, delete the Nginx config and reload Nginx, archive logs to logs/archived/$ENV_ID/, then delete the state file.

2.  Auto Cleanup Daemon
cleanup_daemon.sh loops every 60 seconds. For each file in envs/, it checks if now > created_at + ttl and calls destroy_env.sh if true. Every action must be timestamped and written to logs/cleanup.log. Run it in the background with nohup.

3.  Nginx Dynamic Routing
Nginx is the front door for all environments. On every create, your script writes a config file to nginx/conf.d/$ENV_ID.conf and runs nginx -s reload. On every destroy, the file is deleted and Nginx reloaded again. The main nginx.conf must include conf.d/*.conf. Run Nginx as a Docker container and document your network approach in the README.

4.  Log Shipping
Pick one approach and document it. Approach A (simple): run docker logs -f $CONTAINER\_ID >> logs/$ENV_ID/app.log & at creation, store the PID, kill it on destroy. Approach B (proper): use a log aggregator container (Loki, Fluentd) reading from the Docker socket. Either way, logs must be queryable by env ID via make logs ENV=env-abc123.

5.  Health Monitoring
A poller in monitor/ hits each active env’s GET /health endpoint every 30 seconds and writes timestamp, HTTP status, and latency to logs/$ENV_ID/health.log. After 3 consecutive failures, set the env’s status to “degraded” and print a warning. Prometheus + Grafana integration is optional but earns extra credit.


6.  Outage Simulation
platform/simulate_outage.sh accepts --env and --mode flags:
	•	crash — docker kill the container (health monitor should catch it within 90s)
	•	pause — docker pause (recover with docker unpause)
	•	network — docker network disconnect the container
	•	recover — restore whatever was broken
	•	stress — optional, spike CPU with stress-ng
Add a guard at the top of the script — never run simulation against the Nginx or daemon container.


7.  Control API
A lightweight API (Flask, FastAPI, or Express) wrapping the scripts. Minimum 6 endpoints:

POST   /envs              → create env
GET    /envs              → list active envs + TTL remaining
DELETE /envs/:id          → destroy env
GET    /envs/:id/logs     → last 100 lines of app.log
GET    /envs/:id/health   → last 10 health check results
POST   /envs/:id/outage   → trigger simulation (body: {"mode":"crash"})



8.  Makefile
Every action must have a make target:

make up                      # start Nginx + daemon + API
make down                    # stop everything, destroy all envs
make create                  # create new env (prompts for name + TTL)
make destroy ENV=…           # destroy specific env
make logs ENV=…              # tail env logs
make health                  # show all env health statuses
make simulate ENV=… MODE=…   # run outage simulation
make clean                   # wipe all state, logs, archives


9.  README
Must include: architecture diagram (ASCII or PNG), prerequisites, quick-start from zero to first running env in under 5 commands, a full demo walkthrough (create → deploy → check health → simulate outage → observe → recover → auto-destroy), and known limitations.

Common Mistakes - Don’t Do These
	•	Hardcoding container names or ports —everything must be parameterized by env ID
	•	Forgetting to reload Nginx after every config change
	•	Not killing the log-shipping process on destroy (causes zombie processes)
	•	Writing state files non-atomically — write to a temp file first, then mv into place

N/B
The demo app inside your environments can be anything — a Hello World Express server, a Flask app, a static Nginx server. The platform is the project, not the app inside it.


Submission

A public GitHub Repo containing your correct file structure.
Drive link to your full 3mins walkthrough video of how your app works end to end.
README complete with full setup steps and architecture diagram of your system.

Task Deadline 

Task deadline: 10th May, 2026 11:59AM WAT. Server must be live and passing at time of grading. Also late submission is not accepted

