# Doppler Manager (SOTA Zero-Trust SecretOps)

[![Gemini CLI Skill](https://img.shields.io/badge/Gemini%20CLI-Skill-blue.svg)](https://github.com/google/gemini-cli)
[![Doppler](https://img.shields.io/badge/Doppler-SecretOps-purple.svg)](https://doppler.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **A SOTA (State of the Art) Zero-Leak Secret Management Skill for AI Agents.**

This repository provides the official `skill-doppler-manager` for Gemini CLI and other AI agents. It acts as the "secure hand" for LLMs to manage and inject secrets, completely abolishing the traditional "fetch to local `.env`" workflow in favor of memory-only injection via **Doppler**.

By installing this skill, your AI agents will learn to:
1. 🛑 **Never leak, print, or commit raw secrets.**
2. 💉 **Inject secrets directly into processes using `doppler run`.**
3. 🔐 **Require Human-in-the-Loop (HITL) for secret creation and modification.**

---

## 📖 What's Inside?

- `SKILL.md`: The core neural instructions and operational mandates for the AI agent.
- `spec.md`: The declarative architectural specification and design philosophy.
- `scripts/check_status.sh`: A lightweight, LLM-friendly status check script.
- `references/`: Documentation for human operators and AI context (SOPs, Architecture Decisions).

## 🚀 Installation

This skill is designed to be installed directly into your Gemini CLI environment.

```bash
# 1. Clone this repository
git clone https://github.com/plasmayang/skill-doppler-manager.git

# 2. Package the skill
gemini skills install ./skill-doppler-manager --scope workspace

# 3. Reload Gemini CLI
/skills reload
```

## 🧠 Design Philosophy (Prompt vs. Code)

We strictly separate concerns to optimize LLM context window usage:
- **`SKILL.md` (Prompt):** Behavioral guardrails (Zero-Leak), workflow orchestration (HITL), and injection syntax.
- **`scripts/` (Code):** Deterministic environment checks (e.g., `check_status.sh` returning boolean-like LLM-friendly strings).
- **`references/` (Docs):** Human-centric setup guides and historical architectural decisions.

See `references/architecture_decisions.md` for a deep dive into why we built it this way.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request to improve the SOPs or AI instructions.

## 📜 License

MIT License. See [LICENSE](LICENSE) for details.
