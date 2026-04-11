"""
sm_run tool — execute commands with secrets injected (core feature).
"""

import subprocess
import os
import shlex

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run_with_secrets(command: str, manager: str = "auto", cwd: str = None) -> dict:
    """
    Execute a command with secrets injected via the secret manager.

    Args:
        command: Command to execute
        manager: Manager to use (auto/doppler/vault/aws/gcp/azure/infisical)
        cwd: Working directory

    Returns:
        {stdout, stderr, exit_code}
    """
    script_path = os.path.join(SCRIPT_DIR, "secret_manager_interface.sh")

    cmd = [
        "bash",
        script_path,
        "sm_run",
        "--",
        command,
    ]

    if manager != "auto":
        cmd.insert(3, manager)  # Insert manager after sm_run

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,  # 5 min timeout for long-running commands
            cwd=cwd,
            env={
                **os.environ,
                # Ensure secrets never enter shell history
                "HISTIGNORE": "*",
                "HISTCONTROL": "ignorespace",
            },
        )

        return {
            "stdout": result.stdout[:10000] if result.stdout else "",
            "stderr": result.stderr[:5000] if result.stderr else "",
            "exit_code": result.returncode,
            "truncated": len(result.stdout) > 10000 if result.stdout else False,
        }

    except subprocess.TimeoutExpired:
        return {
            "stdout": "",
            "stderr": "Command timed out after 300 seconds",
            "exit_code": 124,
        }
    except Exception as e:
        return {
            "stdout": "",
            "stderr": str(e),
            "exit_code": 1,
        }
