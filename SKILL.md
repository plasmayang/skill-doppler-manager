---
name: doppler-manager
description: Configure and manage Doppler CLI for secure, zero-leak secret injection. Use this skill when executing applications that require environment variables, or when assisting the user in setting up secret management.
---

# Doppler Manager

## Overview

This skill provides the operational "hands" for interacting with the Doppler CLI. Your primary objective is to facilitate secure, zero-leak secret injection for applications and scripts, acting as an orchestrator between the user's secret store and the execution environment.

## 🛑 The Prime Directive (Zero-Leak)

Under NO CIRCUMSTANCES should you:

1. **Print** raw secrets to the chat interface.
2. **Write** secrets to local `.env` files or any file on disk.
3. **Execute** commands that expose secrets in terminal history (e.g., `echo $SECRET`).

Your only method for utilizing secrets is memory-only injection via the Doppler CLI.

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

## Troubleshooting

- If a `doppler run` command fails with authentication errors, ask the user to verify their token or run `doppler login`.
- If a script fails claiming a missing environment variable, verify with the user that they have set the variable in their active Doppler configuration.
