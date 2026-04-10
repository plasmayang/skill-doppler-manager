---
name: doppler-manager
description: Configure and manage Doppler CLI, including secret management, authentication via Service Tokens, and running commands with secret injection. Use when the user needs to set up Doppler, manage project secrets, or execute applications that depend on Doppler-managed environment variables.
---

# Doppler Manager

## Overview

This skill provides a comprehensive workflow for managing Doppler CLI operations on the local machine. It focuses on authentication, secret lifecycle management, and secure command execution using Doppler's "zero-leak" secret injection.

## Quick Start

1. **Check Environment**: Run `scripts/check_status.sh`. If missing, follow **Task 0: Environment Provisioning**.
2. **Global Auth**: The Codespace is authenticated globally during the `bootstrap.sh` sequence via `doppler login`.
3. **Execute**: Use `doppler run -p <project> -c <config> -- <command>` to inject secrets.

## Core Tasks

### 0. Environment Provisioning

If `doppler` CLI is not found:
- **Research**: Check the OS (e.g., Debian, Ubuntu, macOS).
- **Execute**: Refer to [references/SOP.md](references/SOP.md) for the specific installation commands.
- **Dependencies**: Ensure `curl`, `gnupg`, and `apt-transport-https` are installed if on Linux.
- **Verification**: Run `doppler --version` after installation.

### 1. The 9-Grid Architecture & Logical Just-in-Time Access (JITA)

The `AIandI` workspace strictly isolates secrets across 9 domains (blast radii). Even though the Codespace has global CLI access, **AI Agents MUST NOT access projects other than `keys4_token-providers` without explicit human permission.**

**The 9 Projects:**
1. `keys4_network-core` (Tailscale, Cloudflare)
2. `keys4_network-nodes` (SSH keys for VMs)
3. `keys4_backup-core` (S3/B2 keys, NAS encryption)
4. `keys4_private-services` (DB passwords)
5. `keys4_identity-providers` (OAuth clients, Social/Google/GitHub logins)
6. `keys4_token-providers` (AI API Keys: OpenAI, Anthropic, Gemini) - *Default AI scope*
7. `keys4_observability-telemetry` (Grafana, Datadog)
8. `keys4_notification-channels` (Telegram bots, Webhooks)
9. `keys4_delivery-pipelines` (Docker Hub, NPM)

**The JITA Workflow (User Consent & Zero-Knowledge Injection):**
AI Agents DO NOT read, print, or directly manage the raw contents of secrets. The Doppler cloud stores them; the human configures them. The AI's role is to orchestrate tasks by injecting secrets into subprocesses via `doppler run`.

If you need to execute a command that requires secrets from ANY project *other* than `keys4_token-providers`:
1. Identify the target project from the 9-grid list above.
2. USE THE `ask_user` TOOL (type: `yesno` or `choice`) to explicitly request permission from the human.
   - Example prompt: "I need to inject secrets from the `[project_name]` project to execute this command. Do you authorize this action?"
3. Only if the user explicitly grants permission, you may proceed to use `doppler run -p [project_name] -c stg -- <command>`.

### 2. Secret Management (Human-in-the-Loop)

AI Agents **SHOULD NOT** attempt to read, add, or delete secrets directly using `doppler secrets` commands. Secret configuration is manually managed by the human user to maintain the zero-knowledge boundary.
- If a new secret is needed for a script the AI wrote, or an existing secret needs modification, the AI must ask the user to perform the action.
- **Crucial:** When prompting the user to manage a secret, the AI MUST provide the exact, copy-pasteable `doppler secrets` CLI command for the user to run in their terminal, rather than just telling them to use the Web UI.
  - Example prompt to user: "I need a new secret `DATABASE_URL` in the `keys4_private-services` project. Please run this command to add it: `doppler secrets set DATABASE_URL="<your_value>" -p keys4_private-services -c stg`"
- The AI assumes the secret exists once the user confirms they have run the command.

### 3. Secure Execution (The AI's Primary Role)

The primary duty of the AI is to inject secrets directly into the application's or script's memory using Doppler, ensuring zero secrets are leaked to disk or logs.

- **Run Command**: `doppler run -p <project> -c <config> -- <command>`
- **Example**: `doppler run -p keys4_private-services -c stg -- python3 main.py`
- **Docker Compose**: `doppler run -p keys4_network-core -c stg -- docker compose up -d`

## Reference Documentation

For detailed architecture, security best practices, and SOPs, see [references/SOP.md](references/SOP.md) and `$USERDATA_REPO/30-resources/sops/doppler-architecture-guide.md`.

## Troubleshooting

- **Auth Error**: Ensure the token is correctly set with `doppler configure set token`.
- **Project/Config Error**: The Service Token is strictly bound to one project/config. If you get a 403, you are trying to access the wrong grid in the 9-grid architecture. Use `ask_user` to request the correct token.
- **Network Issues**: Doppler CLI supports offline fallback if a local cache exists. Check `doppler secrets --offline` if connectivity is poor.
