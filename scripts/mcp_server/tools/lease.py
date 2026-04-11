"""
sm_lease tools — get and renew secret leases with TTL.
"""

import subprocess
import os
import json
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def get_lease(secret: str, manager: str = "auto") -> dict:
    """
    Get a secret with TTL lease.

    Args:
        secret: Secret name
        manager: Manager to use

    Returns:
        {value, expires_at, ttl_seconds, renewal_required}
    """
    script_path = os.path.join(SCRIPT_DIR, "secret_lease.sh")

    cmd = [
        "bash",
        script_path,
        "get",
        secret,
    ]

    if manager != "auto":
        cmd.extend(["--manager", manager])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode == 0:
            try:
                data = json.loads(result.stdout)
                return {
                    "value": "***MASKED***",
                    "expires_at": data.get("expires_at", ""),
                    "ttl_seconds": data.get("ttl_seconds", 0),
                    "renewal_required": data.get("ttl_seconds", 0) < 60,
                }
            except json.JSONDecodeError:
                return {
                    "error": "Failed to parse lease response",
                    "raw": result.stdout[:500],
                }
        else:
            return {
                "error": result.stderr.strip() or "Lease not available",
                "manager": manager,
            }

    except subprocess.TimeoutExpired:
        return {"error": "Lease request timed out"}
    except Exception as e:
        return {"error": str(e)}


def renew_lease(secret: str, manager: str = "auto") -> dict:
    """
    Renew a secret lease.

    Args:
        secret: Secret name
        manager: Manager to use

    Returns:
        {expires_at, ttl_seconds}
    """
    script_path = os.path.join(SCRIPT_DIR, "secret_lease.sh")

    cmd = [
        "bash",
        script_path,
        "renew",
        secret,
    ]

    if manager != "auto":
        cmd.extend(["--manager", manager])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode == 0:
            try:
                data = json.loads(result.stdout)
                return {
                    "expires_at": data.get("expires_at", ""),
                    "ttl_seconds": data.get("ttl_seconds", 0),
                }
            except json.JSONDecodeError:
                return {"error": "Failed to parse renew response"}
        else:
            return {
                "error": result.stderr.strip() or "Failed to renew lease",
            }

    except subprocess.TimeoutExpired:
        return {"error": "Renew timed out"}
    except Exception as e:
        return {"error": str(e)}
