#!/usr/bin/env python3
"""
secret-management MCP Server

FastMCP-based server that exposes zero-leak secret management to any AI agent.
"""

import os
import sys
import json
import logging
from typing import Any, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("secret_management_mcp")

# Try to import FastMCP, fall back to base MCP SDK
try:
    from fastmcp import FastMCP

    MCP = FastMCP("secret-management")
    USE_FASTMCP = True
except ImportError:
    try:
        from mcp.server import Server
        from mcp.server.stdio import stdio_server
        import asyncio

        MCP = Server("secret-management")
        USE_FASTMCP = False
        logger.warning("FastMCP not found, using base MCP SDK")
    except ImportError:
        logger.error("No MCP SDK available. Install fastmcp or mcp.")
        sys.exit(1)

# Import tools
from .tools.status import get_status
from .tools.fetch import fetch_secret
from .tools.run import run_with_secrets
from .tools.audit import get_audit_log
from .tools.lease import get_lease, renew_lease
from .tools.rotation import rotate_secret
from .tools.request import request_access

# Import resources
from .resources.secrets import SECRET_RESOURCE_PATTERNS, secret_resource_handler


def _mask_json_output(data: dict, secret_fields: list[str] = None) -> dict:
    """
    Recursively mask secret values in JSON output.
    Zero-leak: secrets never appear in tool responses.
    """
    if secret_fields is None:
        secret_fields = ["value", "secret", "password", "token", "key"]

    masked = {}
    for key, value in data.items():
        if any(secret_field in key.lower() for secret_field in secret_fields):
            if isinstance(value, str) and len(value) > 0:
                masked[key] = "***MASKED***"
            else:
                masked[key] = value
        elif isinstance(value, dict):
            masked[key] = _mask_json_output(value, secret_fields)
        elif isinstance(value, list):
            masked[key] = [
                _mask_json_output(item, secret_fields) if isinstance(item, dict) else item
                for item in value
            ]
        else:
            masked[key] = value
    return masked


# ============================================================
# MCP Resources
# ============================================================

if USE_FASTMCP:

    @MCP.resource("secrets://{manager}/{secret_name}")
    def secret_resource(manager: str, secret_name: str) -> str:
        """
        Access secrets via secret:// URI scheme.

        Format: secret://{manager}/{secret_name}
        Example: secret://doppler/DATABASE_URL

        Returns resource URI, NOT the secret value.
        The secret value is only available via sm_fetch tool.
        """
        return secret_resource_handler(manager, secret_name)

    # Resource templates
    for pattern in SECRET_RESOURCE_PATTERNS:
        MCP.resource.register_resource(pattern)


# ============================================================
# MCP Tools
# ============================================================

if USE_FASTMCP:

    @MCP.tool()
    def sm_status() -> dict:
        """
        Check secret manager health and authentication status.

        Returns structured JSON with status code (E000-E005).
        """
        try:
            result = get_status()
            return result
        except Exception as e:
            logger.error(f"sm_status failed: {e}")
            return {"status": "ERROR", "code": "E999", "message": str(e)}

    @MCP.tool()
    def sm_fetch(secret: str, manager: str = "auto", plain: bool = False) -> dict:
        """
        Retrieve a single secret (memory-only).

        Args:
            secret: Secret name (e.g., DATABASE_URL)
            manager: Manager to use (auto/doppler/vault/aws/gcp/azure/infisical)
            plain: If True, return raw value (use with caution)

        Returns:
            {value, manager, cached, expires_at} or {error}
        """
        try:
            result = fetch_secret(secret, manager, plain)
            # Always mask in logs
            logger.info(f"sm_fetch: {secret} via {result.get('manager', 'unknown')}")
            return _mask_json_output(result) if not plain else result
        except Exception as e:
            logger.error(f"sm_fetch failed: {e}")
            return {"error": str(e)}

    @MCP.tool()
    def sm_run(command: str, manager: str = "auto", cwd: str = None) -> dict:
        """
        Execute a command with secrets injected (core feature).

        Args:
            command: Command to execute (e.g., "python3 main.py")
            manager: Manager to use (auto/doppler/vault/aws/gcp/azure/infisical)
            cwd: Working directory

        Returns:
            {stdout, stderr, exit_code}
        """
        try:
            logger.info(f"sm_run: {command[:50]}...")
            result = run_with_secrets(command, manager, cwd)
            return _mask_json_output(result)
        except Exception as e:
            logger.error(f"sm_run failed: {e}")
            return {"error": str(e)}

    @MCP.tool()
    def sm_audit(manager: str = "auto", limit: int = 100) -> dict:
        """
        Retrieve audit log entries.

        Args:
            manager: Filter by manager (default: all)
            limit: Maximum entries to return

        Returns:
            {entries: [{timestamp, action, manager, secret, result}]}
        """
        try:
            result = get_audit_log(manager, limit)
            return _mask_json_output(result)
        except Exception as e:
            logger.error(f"sm_audit failed: {e}")
            return {"error": str(e)}

    @MCP.tool()
    def sm_lease_get(secret: str, manager: str = "auto") -> dict:
        """
        Get a secret with TTL lease.

        Args:
            secret: Secret name
            manager: Manager to use

        Returns:
            {value, expires_at, ttl_seconds, renewal_required}
        """
        try:
            result = get_lease(secret, manager)
            return _mask_json_output(result)
        except Exception as e:
            logger.error(f"sm_lease_get failed: {e}")
            return {"error": str(e)}

    @MCP.tool()
    def sm_lease_renew(secret: str, manager: str = "auto") -> dict:
        """
        Renew a secret lease.

        Args:
            secret: Secret name
            manager: Manager to use

        Returns:
            {expires_at, ttl_seconds}
        """
        try:
            result = renew_lease(secret, manager)
            return _mask_json_output(result)
        except Exception as e:
            logger.error(f"sm_lease_renew failed: {e}")
            return {"error": str(e)}

    @MCP.tool()
    def sm_rotate(secret: str, manager: str = "auto") -> dict:
        """
        Request secret rotation (requires human approval).

        Args:
            secret: Secret name
            manager: Manager to use

        Returns:
            {request_id, status, approval_required}
        """
        try:
            result = rotate_secret(secret, manager)
            return _mask_json_output(result)
        except Exception as e:
            logger.error(f"sm_rotate failed: {e}")
            return {"error": str(e)}

    @MCP.tool()
    def sm_request(secret: str, reason: str) -> dict:
        """
        Request human approval for secret access.

        Args:
            secret: Secret name
            reason: Business justification

        Returns:
            {request_id, status}
        """
        try:
            result = request_access(secret, reason)
            return result
        except Exception as e:
            logger.error(f"sm_request failed: {e}")
            return {"error": str(e)}


# ============================================================
# Server Entry Point
# ============================================================


def main():
    """Start the MCP server."""
    logger.info(f"Starting secret-management MCP server v{__import__('__main__').__version__}")

    if USE_FASTMCP:
        MCP.run()
    else:
        # Base MCP SDK server
        async def run_server():
            async with stdio_server() as (read_stream, write_stream):
                await MCP.run(read_stream, write_stream)

        asyncio.run(run_server())


if __name__ == "__main__":
    main()
