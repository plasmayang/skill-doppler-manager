# Doppler Manager Skill Specification (SOTA Zero-Trust)

## 1. Overview
This document defines the declarative specification for the `doppler-manager` Skill. The purpose of this skill is to provide LLM agents with the operational capabilities to securely manage and inject secrets using Doppler, adhering strictly to a "Zero-Leak" philosophy.

## 2. Directory Structure
Adhering to the Gemini CLI Skill packaging standards:

```text
doppler-manager/
├── SKILL.md                 # (Required) Core prompt, triggers, and behavioral mandates.
├── references/              # (Optional) Contextual documents read by the AI on demand.
│   ├── SOP.md               # Human-centric guide for installation and authentication.
│   └── architecture_decisions.md # Rationale behind prompt vs. code separation and scope.
└── scripts/                 # (Optional) Executable scripts for deterministic tasks.
    └── check_status.sh      # Validates Doppler CLI installation and auth state.
```

## 3. SKILL.md Specification (Prompt Design)

### 3.1 YAML Frontmatter
Used for precise intent triggering by the orchestrator LLM.

```yaml
---
name: doppler-manager
description: Configure and manage Doppler CLI for secure, zero-leak secret injection. Use this skill when executing applications that require environment variables, or when assisting the user in setting up secret management.
---
```

### 3.2 Core Directives (Body)
**Principle**: Progressive Disclosure. The main prompt contains only critical guardrails and workflow orchestrations. Long lists or human instructions are relegated to `references/`.

**Core Sections:**
1.  **The Prime Directive (Zero-Leak)**: Explicit prohibition against reading/printing plaintext secrets or writing `.env` files.
2.  **Secure Execution**: The mandatory syntax for wrapping execution targets (`doppler run -- <command>`).
3.  **Human-in-the-Loop (HITL)**: The workflow for requesting human intervention when secret mutation is required (e.g., providing the user with `doppler secrets set` commands).

## 4. Scripting Specification (`scripts/`)

Code should be used over Prompting for deterministic state evaluation.

### 4.1 `check_status.sh`
*   **Purpose**: A lightweight, LLM-friendly status check.
*   **Output Requirement**: Must emit concise, parseable strings (e.g., `STATUS: OK` or `STATUS: ERROR`) to conserve token context and prevent the LLM from hallucinating over verbose standard error logs.

## 5. Architectural Boundaries
*   This skill does **not** enforce secret classification topologies (like the legacy 9-Grid system). Classification is a user policy; this skill handles the secure operational execution.
*   See `references/architecture_decisions.md` for the complete rationale on separating Prompt (Behavior) from Code (State).
