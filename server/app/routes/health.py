import time
from datetime import datetime, timezone

from flask import Blueprint, jsonify

health_bp = Blueprint("health", __name__)
START_TIME = time.time()


@health_bp.get("/api/heartbeat")
def heartbeat():
    return jsonify(
        {
            "status": "ok",
            "time": datetime.now(timezone.utc).isoformat(),
            "uptime": int(time.time() - START_TIME),
        }
    )
