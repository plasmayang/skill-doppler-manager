"""
JSON Mask Utilities

Provides consistent secret masking for JSON output across all tools.
"""

import json
import re
from typing import Any, Dict, List, Optional


# Patterns that indicate secret values
SECRET_PATTERNS = [
    r'sk-[A-Za-z0-9]{20,}',           # OpenAI keys
    r'ghp_[A-Za-z0-9]{36}',           # GitHub tokens
    r'xox[baprs]-[A-Za-z0-9]{10,}',  # Slack tokens
    r'AKIA[A-Z0-9]{16}',               # AWS access keys
    r'[A-Za-z0-9+/]{40,}={0,2}',      # Long base64 strings
    r'password["\']?\s*[:=]\s*["\'][^"\']{8,}["\']',  # password=value
]

# Fields that typically contain secrets
SECRET_FIELDS = {
    "value", "secret", "password", "token", "key",
    "api_key", "apiKey", "access_token", "auth",
    "private_key", "client_secret", "bearer", "credential",
}


def mask_value(value: str) -> str:
    """Mask a secret value for display."""
    if not value:
        return ""
    if len(value) <= 8:
        return "***"
    return f"{value[:4]}...{value[-4:]}"


def mask_json(data: Any, depth: int = 0) -> Any:
    """
    Recursively mask secrets in JSON-compatible data.

    Args:
        data: JSON-compatible data structure
        depth: Current recursion depth (prevents infinite loops)

    Returns:
        Data with secrets masked
    """
    if depth > 10:
        return data  # Safety limit

    if isinstance(data, dict):
        result = {}
        for key, value in data.items():
            if key.lower() in SECRET_FIELDS:
                if isinstance(value, str):
                    result[key] = mask_value(value)
                else:
                    result[key] = "***"
            else:
                result[key] = mask_json(value, depth + 1)
        return result

    elif isinstance(data, list):
        return [mask_json(item, depth + 1) for item in data]

    elif isinstance(data, str):
        # Check if the string itself matches a secret pattern
        for pattern in SECRET_PATTERNS:
            if re.search(pattern, data):
                return mask_value(data)
        return data

    return data


def to_json(data: Any, mask: bool = True, indent: Optional[int] = 2) -> str:
    """
    Serialize data to JSON string with optional secret masking.

    Args:
        data: Data to serialize
        mask: Whether to mask secrets
        indent: JSON indent level

    Returns:
        JSON string
    """
    if mask:
        data = mask_json(data)
    return json.dumps(data, indent=indent, default=str)
