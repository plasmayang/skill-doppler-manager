"""
Zero-Leak Enforcement Utilities

Ensures secrets never leak through:
- Process listings
- Shell history
- Temporary files
- Log output
"""

import os
import re
from typing import Optional


def mask_secret(value: str, secret_name: Optional[str] = None) -> str:
    """
    Mask a secret value for safe display.

    Args:
        value: The secret value
        secret_name: Optional name for partial masking

    Returns:
        Masked string (e.g., "sk-...xxxx")
    """
    if not value:
        return ""

    if len(value) <= 8:
        return "***"

    return f"{value[:4]}...{value[-4:]}"


def sanitize_for_json(obj: dict, secret_fields: Optional[list] = None) -> dict:
    """
    Recursively sanitize dict for JSON output.

    Removes or masks any field that looks like a secret.

    Args:
        obj: Dict to sanitize
        secret_fields: List of field names to mask (default: common secret patterns)

    Returns:
        Sanitized dict
    """
    if secret_fields is None:
        secret_fields = [
            "value", "secret", "password", "token", "key",
            "api_key", "apiKey", "access_token", "auth_token",
            "private_key", "client_secret", "bearer",
        ]

    if not isinstance(obj, dict):
        return obj

    result = {}
    for key, value in obj.items():
        key_lower = key.lower()
        if any(secret_field in key_lower for secret_field in secret_fields):
            if isinstance(value, str) and value:
                result[key] = mask_secret(value, key)
            else:
                result[key] = "***"
        elif isinstance(value, dict):
            result[key] = sanitize_for_json(value, secret_fields)
        elif isinstance(value, list):
            result[key] = [
                sanitize_for_json(v, secret_fields) if isinstance(v, dict) else v
                for v in value
            ]
        else:
            result[key] = value

    return result


def detect_leak_in_string(text: str) -> Optional[str]:
    """
    Heuristically detect if a string contains a leaked secret.

    Returns:
        Description of potential leak or None
    """
    if not text:
        return None

    patterns = [
        (r'sk-[A-Za-z0-9]{20,}', 'OpenAI API key pattern'),
        (r'ghp_[A-Za-z0-9]{36}', 'GitHub personal access token'),
        (r'xox[baprs]-[A-Za-z0-9]{10,}', 'Slack token pattern'),
        (r'AKIA[A-Z0-9]{16}', 'AWS access key ID'),
        (r'[A-Za-z0-9+/]{40,}==?', 'Base64-encoded secret pattern'),
    ]

    for pattern, description in patterns:
        if re.search(pattern, text):
            return f"Potential secret leak detected: {description}"

    return None


def ensure_clean_environment():
    """
    Ensure the current environment won't leak secrets.

    Call this before running any command with secrets.
    """
    # Disable shell history
    os.environ["HISTIGNORE"] = "*"
    os.environ["HISTCONTROL"] = "ignorespace"

    # Ensure temp directory is secure
    if "TMPDIR" not in os.environ:
        os.environ["TMPDIR"] = "/tmp"
