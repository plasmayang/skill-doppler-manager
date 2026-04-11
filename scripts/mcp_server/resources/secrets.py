"""
Secret Resource Handlers

Implements secret:// URI scheme for MCP resources.
"""

from typing import Dict

# Supported managers
MANAGERS = ["doppler", "vault", "aws", "gcp", "azure", "infisical"]

# URI patterns for resource registration
SECRET_RESOURCE_PATTERNS = [
    f"secrets://{{{manager}}}/{{{{secret_name}}}}" for manager in MANAGERS
]


def secret_resource_handler(manager: str, secret_name: str) -> Dict:
    """
    Handle secret://{manager}/{secret} resource request.

    Returns the resource URI, NOT the secret value.
    This maintains zero-leak: AI agent gets URI reference, not secret.

    Args:
        manager: Secret manager name
        secret_name: Name of the secret

    Returns:
        Resource metadata dict
    """
    if manager not in MANAGERS:
        return {
            "error": f"Unknown manager: {manager}",
            "supported": MANAGERS,
        }

    return {
        "uri": f"secret://{manager}/{secret_name}",
        "manager": manager,
        "secret": secret_name,
        "note": "Use sm_fetch tool to retrieve secret value",
    }
