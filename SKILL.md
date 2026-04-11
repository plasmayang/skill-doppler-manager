---
name: secret-management
description: Zero-leak secret management for AI agents. Configure and manage secret managers (Doppler, Vault, AWS, GCP, Azure) for secure, memory-only secret injection. Use this skill when executing applications that require secrets, or when assisting the user in setting up secret management.
---

# Doppler Manager (Multi-Secret-Manager Support)

## Overview

This skill provides the operational "hands" for interacting with secret managers. Your primary objective is to facilitate secure, zero-leak secret injection for applications and scripts, acting as an orchestrator between the user's secret store and the execution environment.

**Supported Secret Managers:**

- Doppler CLI (primary)
- HashiCorp Vault
- AWS Secrets Manager
- GCP Secret Manager
- Azure Key Vault
- Infisical

**Auto-Detection:** The skill can automatically detect available secret managers using `scripts/detect_manager.sh`.

## 🛑 The Prime Directive (Zero-Leak)

Under NO CIRCUMSTANCES should you:

1. **Print** raw secrets to the chat interface.
2. **Write** secrets to local `.env` files or any file on disk.
3. **Execute** commands that expose secrets in terminal history (e.g., `echo $SECRET`).

Your only method for utilizing secrets is memory-only injection via the active secret manager (`doppler run`, `vault run`, etc.).

## Quick Start

1. **Check Environment:** Always start by running `scripts/check_status.sh`. If it reports an error, refer to `references/SOP.md` to help the user install or authenticate the CLI.
2. **Execute:** Use `doppler run -- <command>` to inject secrets into a process.

## Core Workflows

### 1. Secure Execution (Injection)

When asked to run a script, start a server, or execute any process that requires environment variables managed by Doppler, you MUST use `doppler run`.

- **Syntax:** `doppler run -- <command>`
- **Example (Python):** `doppler run -- python3 main.py`
- **Example (Docker):** `doppler run -- docker compose up -d`
- *Note: If the user explicitly specifies a project and config, use `doppler run -p <project> -c <config> -- <command>`.*

### 2. Secret Management (Human-in-the-Loop)

You DO NOT directly create, update, or delete secrets using the `doppler secrets set` commands autonomously. You must rely on the human user to perform these mutations to maintain the zero-knowledge boundary.

- If a new secret is needed (e.g., you wrote a script requiring `OPENAI_API_KEY`), you must ask the user to add it.
- **Crucial:** Provide the exact, copy-pasteable CLI command for the user to run.
  - *Example Prompt to User:* "I have updated the script to use `DATABASE_URL`. Please run the following command in your terminal to set this secret in Doppler before we proceed: `doppler secrets set DATABASE_URL="<your_value>"`"
- Wait for the user to confirm they have set the secret before attempting to run the application.

### 3. Environment Provisioning

If `scripts/check_status.sh` indicates Doppler is not installed or not authenticated:

- Read `references/SOP.md` for the correct installation instructions based on the OS.
- Guide the user through the `doppler login` process.

## Structured Status Check

Always use `scripts/check_status.sh` to check environment status. It outputs structured JSON:

```json
{
  "status": "OK|WARNING|ERROR",
  "code": "E000|E001|...",
  "message": "Human-readable description",
  "hint": "Recovery action to suggest to user",
  "documentation": "references/SOP.md#section",
  "project": "project-name",
  "config": "config-name"
}
```

### Error Code Reference

| Code | Status | Meaning | Recovery |
| --- | --- | --- | --- |
| E000 | OK | Authenticated and configured | Ready to use |
| E001 | ERROR | Doppler CLI not installed | Install via `brew install doppler-cli` or see SOP.md#phase-1 |
| E002 | ERROR | Not authenticated | Run `doppler login` |
| E003 | ERROR | Token expired | Run `doppler login` to re-authenticate |
| E004 | WARNING | No project/config set | Run `doppler setup` in project directory |
| E005 | ERROR | Permission denied | Verify Doppler access token permissions |
| E006 | ERROR | Network error | Check internet connection and VPN |
| E007 | ERROR | Config mismatch | Run `doppler setup --project <proj> --config <cfg>` |

## Troubleshooting

When `check_status.sh` returns an error:

1. **Parse the JSON** - Extract `code`, `message`, and `hint` fields
2. **Present the hint** - Show the user the recommended recovery command
3. **Reference documentation** - Point to the relevant SOP.md section
4. **Wait for confirmation** - Do not proceed until user confirms recovery action

- If a `doppler run` command fails, re-run `scripts/check_status.sh` to get updated status.
- If a script fails claiming a missing environment variable, verify with the user that they have set the variable in their active Doppler configuration.

## Advanced Workflows

### 4. Multi-Environment Execution

When working with multiple environments (dev/stg/prd), always verify the target environment before execution:

```bash
# Check current configured environment
doppler configure get config --plain

# For production-critical operations, explicitly specify project/config
doppler run -p <project> -c prd -- <command>
```

**Rule**: Never assume the current environment. Always verify with `doppler configure get config` before destructive operations.

### 5. Secret Rotation Support

When secrets are rotated, the LLM should detect stale secret errors and trigger a re-authentication flow:

**Detection**: If `doppler run` fails with auth/secrets errors after previously working:

1. Run `scripts/check_status.sh` to assess
2. If E003 (TOKEN_EXPIRED) or new auth errors, inform the user
3. Provide the re-authentication command: `doppler login`
4. After re-auth, re-verify with `scripts/check_status.sh`

**HITL for Rotation**: If the user mentions secret rotation:

- Do NOT automatically re-fetch secrets
- Ask the user to confirm the rotation is complete and to re-run `doppler login` if needed

### 6. CI/CD and Headless Environments

For non-interactive environments, use Service Tokens instead of interactive login:

**Configuration**:

```bash
doppler configure set token dp.st.xxxxxx
```

**Verification**: For headless environments, you may proactively check the token type:

```bash
doppler configure get token --plain | grep -q "dp.st." && echo "SERVICE_TOKEN" || echo "USER_TOKEN"
```

**Rules for Headless**:

- Do NOT attempt interactive `doppler login` in headless mode
- If token is a user token in headless context, warn the user about potential auth expiry
- Recommend migrating to Service Tokens for persistent environments

### 7. Secret Leak Detection & Response

**If you accidentally receive a secret in context** (e.g., user pastes it):

1. **NEVER echo, repeat, or acknowledge the secret value**
2. **immediately** run `/claude/audit log` or the audit script if available
3. Inform the user: "I've detected a secret in the input. For security, I will not process it. Please use the Doppler CLI to set this secret instead."
4. Provide the appropriate `doppler secrets set` command template without the actual value
5. Clear any memory of the value

**Audit Requirement**: Any detected leak attempt should be logged via `scripts/audit_secrets.sh` if available.

### 8. Secret Access Patterns

**Allowed Patterns**:

- `doppler run -- <command>` - Direct injection (recommended)
- `doppler secrets get <KEY> --plain` - Only when the value is immediately consumed and not displayed

**Forbidden Patterns** (NEVER do these):

- `echo $SECRET` or any printing of secrets
- Writing secrets to any file (`.env`, `config.json`, logs, etc.)
- Passing secrets as command-line arguments that get logged
- Including secrets in error messages or stack traces
- Storing secrets in shell history via `HISTCONTROL=ignorespace` (the leak persists)

### 9. Timeout and Retry Handling

When `doppler run` times out or fails transiently:

1. First failure: Re-run `scripts/check_status.sh` to verify auth is still valid
2. If status is OK, retry the command once
3. If second failure: Present the error to user and suggest:
   - Checking Doppler dashboard for outages
   - Verifying network connectivity
   - Using `--no-cache` flag if available: `doppler run --no-cache -- <command>`

## Security Hardening Checklist

Before any secret operation, verify:

- [ ] Secret manager CLI is from official source (not a fork)
- [ ] Token/credentials have minimal required permissions (principle of least privilege)
- [ ] No `.env` files exist in the project (legacy secret contamination)
- [ ] Shell history does not contain secrets (`history -c` if suspected)
- [ ] No hardcoded secrets in scripts or code

## Multi-Secret-Manager Support

When multiple secret managers are available, the skill auto-detects and uses the best one:

### Auto-Detection

Run `scripts/detect_manager.sh` to see available managers:

```bash
# Output shows detected managers with priorities:
# doppler        [Priority: 100] Doppler CLI installed and authenticated
# vault          [Priority: 80]  Vault CLI installed and reachable
```

### Manager-Specific Commands

Each manager has equivalent operations. **Note:** Only Doppler and Infisical support true secret injection via `sm_run`. Vault, AWS, GCP, and Azure retrieve individual secrets and require per-secret access patterns.

| Operation | Doppler | Infisical | Vault | AWS/GCP/Azure |
| --- | --- | --- | --- | --- |
| Status | `doppler configure` | `infisical status` | `vault status` | Manager-specific |
| **Run (Injection)** | `doppler run -- <cmd>` | `infisical run -- <cmd>` | Per-secret fetch | Per-secret fetch |
| Get Secret | `doppler secrets get` | `infisical secrets get` | `vault kv get` | Manager-specific |
| Set (HITL) | `doppler secrets set` | `infisical secrets set` | `vault kv put` | Manager-specific |

**Injection Support:**

- **Full injection**: Doppler, Infisical - these support `sm_run` which injects all secrets as environment variables
- **Per-secret only**: Vault, AWS, GCP, Azure - these require `sm_get <secret_name>` for each needed secret

### Manager Selection Rules

1. **Priority**: Higher priority manager is auto-selected if multiple are available
2. **Doppler is primary**: If Doppler is configured, prefer it for consistency
3. **Explicit override**: User can explicitly request a specific manager
4. **Fallback**: If primary fails, offer alternatives

### Interface Functions (Advanced)

For programmatic access, use the manager interface:

```bash
# Load a specific manager
source scripts/secret_manager_interface.sh
sm_load doppler

# Use standard interface (same for all managers)
sm_status              # Returns JSON status
sm_run <cmd>          # Run with secrets injected
sm_get <secret_name>  # Get single secret (memory-only)
sm_set <secret_name>  # Output HITL command template
```

### Extended Error Codes

| Code | Status | Meaning | Recovery |
| --- | --- | --- | --- |
| E100 | ERROR | Manager not supported | Use `detect_manager.sh` to see available |
| E101 | ERROR | Manager not configured | Run manager-specific setup |
| E102 | ERROR | Manager-specific error | Check manager documentation |

## Emergency Response

If a secret leak is suspected or confirmed:

1. **Immediately** stop all operations involving that secret
2. **Do NOT** attempt to "fix" by overwriting - this destroys audit evidence
3. **Run**: `scripts/emergency_seal.sh` if available to:
   - Capture audit trail
   - Disable affected credentials
   - Generate incident report
4. **Escalate**: Notify the user to rotate the leaked secret immediately via Doppler dashboard
5. **Document**: Log the incident in project records

---

## Error Code Reference (Complete)

| Code | Status | Meaning | Recovery |
| --- | --- | --- | --- |
| E000 | OK | Authenticated and configured | Ready to use |
| E001 | ERROR | Doppler CLI not installed | Install via `brew install doppler-cli` or see SOP.md#phase-1 |
| E002 | ERROR | Not authenticated | Run `doppler login` |
| E003 | ERROR | Token expired | Run `doppler login` to re-authenticate |
| E004 | WARNING | No project/config set | Run `doppler setup` in project directory |
| E005 | ERROR | Permission denied | Verify Doppler access token permissions |
| E006 | ERROR | Network error | Check internet connection and VPN |
| E007 | ERROR | Config mismatch | Run `doppler setup --project <proj> --config <cfg>` |
