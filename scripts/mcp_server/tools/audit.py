"""
sm_audit tool — retrieve and query audit log entries.
"""

import json
import subprocess
import os
from typing import Optional, List

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def get_audit_log(manager: str = "auto", limit: int = 100) -> dict:
    """
    Retrieve audit log entries.

    Args:
        manager: Filter by manager (auto/doppler/vault/aws/gcp/azure/infisical)
        limit: Maximum entries to return

    Returns:
        {entries: [{timestamp, action, manager, secret, result, user}]}
    """
    script_path = os.path.join(SCRIPT_DIR, "audit_secrets.sh")

    cmd = [
        "bash",
        script_path,
        "--query",
    ]

    if manager != "auto":
        cmd.extend(["--manager", manager])

    cmd.extend(["--limit", str(limit)])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode == 0 and result.stdout.strip():
            try:
                entries = json.loads(result.stdout)
                return {
                    "entries": entries if isinstance(entries, list) else [entries],
                    "count": len(entries) if isinstance(entries, list) else 1,
                    "manager": manager,
                }
            except json.JSONDecodeError:
                return {
                    "entries": [],
                    "raw": result.stdout[:1000],
                    "error": "Failed to parse audit log",
                }
        else:
            return {
                "entries": [],
                "stderr": result.stderr.strip(),
                "manager": manager,
            }

    except subprocess.TimeoutExpired:
        return {"entries": [], "error": "Audit query timed out"}
    except Exception as e:
        return {"entries": [], "error": str(e)}
