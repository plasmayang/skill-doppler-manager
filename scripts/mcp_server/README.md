# secret-management MCP Server

Exposes zero-leak secret management to **any MCP-compatible AI agent**.

## Quick Start

```bash
# Install
pip install -e .

# Run standalone
python -m secret_management_mcp.server

# Or use with Claude Code
claude mcp add secret-management -- python -m secret_management_mcp.server
```

## Tools

| Tool | Description |
|------|-------------|
| `sm_status` | Check manager health |
| `sm_fetch` | Get a secret (masked) |
| `sm_run` | Execute with secrets injected |
| `sm_audit` | Query audit logs |
| `sm_lease_get` | Get secret with TTL |
| `sm_lease_renew` | Renew a lease |
| `sm_rotate` | Request rotation (HITL) |
| `sm_request` | Request access approval |

## Security

- Secrets never appear in tool responses
- Memory-only injection
- Shell history disabled
- Audit logging for all access

## Status

**Planned for v2.1.0** — Design and skeleton complete.
