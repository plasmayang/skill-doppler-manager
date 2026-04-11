# MCP Server Design — secret-management

## Overview

This document describes the design for the Model Context Protocol (MCP) server that exposes `secret-management` capabilities to **any AI agent** (Claude Code, Cursor, Windsurf, Codex, Gemini CLI).

## Why MCP?

Currently this project only works with Claude Code via `SKILL.md`. MCP server makes the same capabilities available to all AI agent frameworks:

- **Cursor** — via MCP protocol
- **Windsurf** — via MCP protocol
- **OpenAI Codex** — via MCP protocol
- **Gemini CLI** — via MCP protocol
- **Any future AI agent** — via standard MCP

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  AI Agent (any MCP-compatible client)                   │
└─────────────────┬───────────────────────────────────────┘
                  │ MCP (JSON-RPC over stdio)
┌─────────────────▼───────────────────────────────────────┐
│  secret-management-mcp-server                            │
│  ├── Resources: secret://{manager}/{secret_name}          │
│  ├── Tools: sm_run, sm_fetch, sm_status, sm_audit       │
│  └── Notifications: lease_expiry, rotation_detected      │
└─────────────────┬───────────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┬─────────────┐
    ▼             ▼             ▼             ▼
Doppler CLI   Vault CLI    AWS CLI     GCP CLI
```

## MCP Capabilities

### Resources

| URI | Description |
|-----|-------------|
| `secret://doppler/{secret}` | Fetch secret from Doppler |
| `secret://vault/{secret}` | Fetch secret from Vault |
| `secret://aws/{secret}` | Fetch secret from AWS Secrets Manager |
| `secret://gcp/{secret}` | Fetch secret from GCP Secret Manager |
| `secret://azure/{secret}` | Fetch secret from Azure Key Vault |
| `secret://infisical/{secret}` | Fetch secret from Infisical |

### Tools

| Tool | Parameters | Returns |
|------|-----------|---------|
| `sm_run` | `command: string`, `manager?: string` | `{stdout, stderr, exit_code}` |
| `sm_fetch` | `secret: string`, `manager?: string`, `plain?: bool` | `{value, manager, cached}` |
| `sm_status` | — | `{status, code, manager, project, config}` |
| `sm_audit` | `manager?: string`, `limit?: int` | `{entries: AuditEntry[]}` |
| `sm_lease_get` | `secret: string`, `manager?: string` | `{value, expires_at, ttl_seconds}` |
| `sm_lease_renew` | `secret: string`, `manager?: string` | `{expires_at, ttl_seconds}` |
| `sm_rotate` | `secret: string`, `manager?: string` | `{rotated_at, new_version}` |
| `sm_request` | `secret: string`, `reason: string` | `{request_id, status}` |

### Notifications (Server → Client)

| Event | Trigger |
|-------|---------|
| `lease_expiring` | Secret lease expires in < 60 seconds |
| `lease_expired` | Secret lease has expired |
| `rotation_detected` | Secret value changed after fetch |

## Security Model

### Zero-Leak Enforcement

All secrets must:

1. **Never appear in tool responses** — only resource URIs
2. **Never touch disk** — memory-only injection via `doppler run`
3. **Never enter shell history** — via `HISTIGNORE` and `set +o history`
4. **Never appear in logs** — JSON output masks secret values

### Human-in-the-Loop

- `sm_rotate` requires human approval via `sm_request`
- `sm_set` (if added) requires human approval
- Emergency seal bypasses approval for incident response only

## Implementation

### Tech Stack

- **Runtime**: Python 3.10+ or Node.js 20+
- **MCP SDK**: `mcp` (Python) or `@modelcontextprotocol/sdk` (TypeScript)
- **Secret CLI wrappers**: Reuse existing `scripts/managers/*.sh`

### File Structure

```
scripts/mcp_server/
  __init__.py
  server.py           # FastMCP server implementation
  resources/
    __init__.py
    secrets.py         # secret:// URI handler
  tools/
    __init__.py
    run.py             # sm_run tool
    fetch.py            # sm_fetch tool
    status.py           # sm_status tool
    audit.py            # sm_audit tool
    lease.py            # sm_lease_* tools
    rotation.py         # sm_rotate tool
    request.py          # sm_request tool
  notifications/
    __init__.py
    lease_monitor.py   # Background lease expiry checker
  utils/
    __init__.py
    leak_detection.py  # Zero-leak enforcement
    json_mask.py        # Secret masking for JSON output
```

## Installation

```bash
# Claude Code
claude mcp add secret-management -- python -m secret_management_mcp

# Cursor
# Add to Cursor settings > MCP Servers

# Manual
python -m secret_management_mcp
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_MANAGER` | `auto` | Preferred manager (doppler/vault/aws/gcp/azure/infisical/auto) |
| `SECRET_CACHE_TTL` | `300` | Secret cache TTL in seconds |
| `LEASE_CHECK_INTERVAL` | `30` | Lease expiry check interval in seconds |
| `AUDIT_LOG_PATH` | `~/.cache/doppler-manager/audit.jsonl` | Audit log location |

## Status

Planned for v2.1.0 — This is a design document.
