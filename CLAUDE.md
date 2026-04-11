# Doppler Manager - Claude Code Skill

Zero-Trust SecretOps for AI Agents - Memory-Only Secret Injection

## Skill Entry Point

This is the top-level entry point for the Doppler Manager skill. For detailed behavioral mandates, operational workflows, and tool references, see `.claude/skills/doppler-skill/skill.md`.

## Quick Start

1. **Check Environment:** Run `sm_status` to verify secret manager configuration
2. **Run Commands:** Use `sm_run` to execute commands with secrets injected
3. **Fetch Secrets:** Use `sm_fetch` for individual secret retrieval

## Available Tools

| Tool | Purpose |
| --- | --- |
| `sm_status` | Check secret manager health and authentication |
| `sm_run` | Execute commands with secrets injected (core feature) |
| `sm_fetch` | Retrieve a single secret (memory-only) |
| `sm_audit` | Log and audit secret access patterns |
| `sm_emergency` | Respond to suspected or confirmed secret leaks |
| `sm_lease` | Retrieve secrets with time-to-live leases |
| `sm_rotate` | Trigger secret rotation |
| `sm_request` | Request secret access (human-in-the-loop) |

## Supported Secret Managers

- Doppler CLI (primary, full injection support)
- HashiCorp Vault (per-secret access)
- AWS Secrets Manager (per-secret access)
- GCP Secret Manager (per-secret access)
- Azure Key Vault (per-secret access)
- Infisical (full injection support)

## The Prime Directive (Zero-Leak)

Under no circumstances should you:

- Print raw secrets to the chat interface
- Write secrets to local files on disk
- Execute commands that expose secrets in terminal history

Your only method for utilizing secrets is memory-only injection via the active secret manager.

## Error Codes

| Code | Status | Meaning |
| --- | --- | --- |
| E000 | OK | Authenticated and configured |
| E001 | ERROR | CLI not installed |
| E002 | ERROR | Not authenticated |
| E003 | ERROR | Token expired |
| E004 | WARNING | No project/config set |
| E005 | ERROR | Permission denied |

## Documentation

- Core Skill: `.claude/skills/doppler-skill/skill.md`
- Operational SOP: `references/SOP.md`
- Error Codes: `scripts/error_codes.sh`
- Status Check: `scripts/check_status.sh`
