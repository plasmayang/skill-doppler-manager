# Doppler Manager Architecture & Design Decisions

## Core Intent
This skill acts as the "hand" for an LLM to manage secrets using Doppler. It is intentionally designed to be an orchestrator, not a policy engine.

## The Scope Boundary (Why we removed the 9-Grid)
Earlier iterations of this skill included a "9-Grid Architecture" for secret classification. We have explicitly removed this because:
1. **Separation of Concerns:** How a user classifies and organizes their secrets (e.g., 9-Grid, by-service, by-environment) is a *human policy* decision. This skill's responsibility is purely operational—how to securely fetch and inject those secrets, regardless of the underlying organizational schema.
2. **Context Economy:** Hardcoding specific architectures into the AI's prompt wastes valuable token context on rules that may not apply to every user's workspace.

## Prompt vs. Code: What goes where?

To ensure this skill remains performant, secure, and maintainable, we strictly divide responsibilities between the AI Prompt (`SKILL.md`) and executable scripts (`scripts/`).

### 1. Solidified into Prompt (`SKILL.md`)
The prompt is reserved for behavioral guardrails, cognitive workflows, and interaction protocols that require LLM reasoning.
*   **The Prime Directive (Zero-Leak):** The absolute rule never to print, log, or write secrets to disk (e.g., `.env` files).
*   **The Injection Workflow:** The mandate to use `doppler run -- <command>` for execution.
*   **Human-in-the-Loop (HITL) Triggers:** When and how to use the `ask_user` tool (e.g., requesting authorization before injecting secrets into a new service, or asking the user to manually add a secret via the CLI).
*   **Error Handling Strategy:** How the AI should react when a Doppler command fails (e.g., checking auth status).

### 2. Solidified into Code (`scripts/`)
Executable code handles deterministic state checks, formatting, and operations that do not require LLM reasoning.
*   **Environment Verification (`check_status.sh`):** Determines if the CLI is installed and authenticated. By pushing this to a script, we guarantee a deterministic, LLM-friendly output (`STATUS: OK / ERROR`), preventing the LLM from hallucinating terminal output or wasting tokens parsing verbose help menus.
*   **Future Automation:** Any complex multi-step CLI sequence that doesn't require dynamic LLM decision-making should be encapsulated in a bash or python script within this directory.

### 3. Solidified into Documentation (`references/SOP.md`)
Documentation is for human operators and for the LLM to read *only when explicitly needed* (e.g., during initial setup).
*   **Installation Commands:** OS-specific curl/apt/brew commands for installing the Doppler CLI.
*   **Authentication Guides:** How a human should generate a Service Token or use `doppler login`.
*   *(Historical Note: We have scrubbed all historical project-specific baggage, such as "iron-web-core" or personal homelab setups, to ensure this skill is a generic, open-source primitive.)*
