"""
sm_fetch tool — retrieve a single secret (memory-only).
"""

import subprocess
import os

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def fetch_secret(secret: str, manager: str = "auto", plain: bool = False) -> dict:
    """
    Fetch a secret using the secret_manager_interface.sh.

    Args:
        secret: Secret name
        manager: Manager to use (auto/doppler/vault/aws/gcp/azure/infisical)
        plain: Return raw value (use with caution)

    Returns:
        {value, manager, cached, expires_at}
    """
    script_path = os.path.join(SCRIPT_DIR, "secret_manager_interface.sh")

    cmd = [
        "bash",
        script_path,
        "sm_fetch",
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
            env={**os.environ, "SM_PLAIN": "1" if plain else "0"},
        )

        if result.returncode == 0:
            return {
                "value": result.stdout.strip() if plain else "***MASKED***",
                "manager": _detect_manager_from_output(result.stderr) or manager,
                "cached": False,
                "note": "Set plain=true to see raw value" if not plain else "",
            }
        else:
            return {
                "error": result.stderr.strip() or "Failed to fetch secret",
                "code": result.returncode,
            }

    except subprocess.TimeoutExpired:
        return {"error": "Fetch timed out"}
    except Exception as e:
        return {"error": str(e)}


def _detect_manager_from_output(stderr: str) -> str:
    """Detect which manager was used from stderr output."""
    for manager in ["doppler", "vault", "aws", "gcp", "azure", "infisical"]:
        if manager in stderr.lower():
            return manager
    return "auto"
