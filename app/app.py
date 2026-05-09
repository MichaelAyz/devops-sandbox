from flask import Flask, jsonify
import os
import time

app = Flask(__name__)
start_time = time.time()


@app.route("/")
def index():
    return jsonify(
        {
            "env": os.environ.get("ENV_ID", "unknown"),
            "status": "running",
            "message": "Hello from DevOps Sandbox",
        }
    )


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "uptime": round(time.time() - start_time, 2)})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
