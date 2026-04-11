"""
sm_request tool — request human approval for secret access.
"""

import subprocess
import os
import json
import uuid
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def request_access(secret: str, reason: str) -> dict:
    """
    Request human approval for secret access.

    Args:
        secret: Secret name
        reason: Business justification

    Returns:
        {request_id, status, created_at, expires_at}
    """
    script_path = os.path.join(SCRIPT_DIR, "access_request.sh")

    request_id = str(uuid.uuid4())[:8]
    created_at = datetime.now(timezone.utc).isoformat()

    # Create the access request via the shell script
    cmd = [
        "bash",
        script_path,
        "create",
        secret,
        "--reason",
        reason,
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "REQUEST_ID": request_id},
        )

        if result.returncode == 0:
            try:
                data = json.loads(result.stdout)
                return {
                    "request_id": request_id,
                    "status": data.get("status", "pending"),
                    "created_at": created_at,
                    "secret": secret,
                    "reason": reason,
                    "approval_url": data.get("approval_url", ""),
                }
            except json.JSONDecodeError:
                pass

        # Fallback: return the request metadata
        return {
            "request_id": request_id,
            "status": "pending",
            "created_at": created_at,
            "secret": secret,
            "reason": reason,
            "note": "Use sm_status to check request status",
        }

    except subprocess.TimeoutExpired:
        return {
            "request_id": request_id,
            "status": "error",
            "error": "Request creation timed out",
        }
    except Exception as e:
        return {
            "request_id": request_id,
            "status": "error",
            "error": str(e),
        }
