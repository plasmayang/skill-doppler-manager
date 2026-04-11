"""
sm_status tool — check secret manager health and authentication.
"""

import json
import subprocess
import os

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def get_status() -> dict:
    """
    Check environment status by running check_status.sh.

    Returns:
        Structured JSON with status, code, message, hint, project, config.
    """
    script_path = os.path.join(SCRIPT_DIR, "check_status.sh")

    try:
        result = subprocess.run(
            ["bash", script_path],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "NO_COLOR": "1"},
        )

        # Try to parse JSON output
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            # Fallback to parsing stdout text
            return {
                "status": "WARNING",
                "code": "E999",
                "message": result.stdout.strip() or result.stderr.strip() or "Unknown error",
                "raw_output": result.stdout[:500] if result.stdout else "",
            }

    except subprocess.TimeoutExpired:
        return {
            "status": "ERROR",
            "code": "E999",
            "message": "Status check timed out",
        }
    except FileNotFoundError:
        return {
            "status": "ERROR",
            "code": "E001",
            "message": "bash not found",
        }
    except Exception as e:
        return {
            "status": "ERROR",
            "code": "E999",
            "message": str(e),
        }
