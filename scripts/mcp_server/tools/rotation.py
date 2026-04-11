"""
sm_rotate tool — trigger secret rotation (requires human approval).
"""

import subprocess
import os
import json
import uuid

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rotate_secret(secret: str, manager: str = "auto") -> dict:
    """
    Request secret rotation. Requires human approval via sm_request.

    Args:
        secret: Secret name
        manager: Manager to use

    Returns:
        {request_id, status, approval_required, command}
    """
    # Generate a request ID
    request_id = str(uuid.uuid4())[:8]

    # Return template command for human to execute
    # Zero-leak: AI cannot rotate secrets autonomously
    return {
        "request_id": request_id,
        "status": "pending_approval",
        "approval_required": True,
        "message": "Secret rotation requires human approval",
        "command": _get_rotation_command(secret, manager),
        "note": "Execute the command above to rotate, then confirm completion",
    }


def _get_rotation_command(secret: str, manager: str = "auto") -> str:
    """Generate the rotation command for the user."""
    if manager == "doppler" or manager == "auto":
        return f"doppler secrets set {secret}=<new_value>  # Rotation for {secret}"
    elif manager == "vault":
        return f"vault kv put secret/{secret} value=<new_value>  # Rotation for {secret}"
    elif manager == "aws":
        return f"aws secretsmanager update-secret --secret-id {secret} --secret-string <new_value>"
    elif manager == "gcp":
        return f"gcloud secrets versions add {secret} --data-file=-  # Rotation for {secret}"
    elif manager == "azure":
        return f"az keyvault secret set --vault-name <vault> --name {secret} --value <new_value>"
    elif manager == "infisical":
        return f"infisical secrets set {secret}=<new_value>  # Rotation for {secret}"
    else:
        return f"# Unknown manager: {manager}. Please use your secret manager CLI directly."
