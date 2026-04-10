# 🛡️ Skill: Doppler Manager (Zero-Trust SecretOps)

[![Gemini CLI Skill](https://img.shields.io/badge/Gemini%20CLI-Skill-blue.svg)](https://github.com/google/gemini-cli)
[![Doppler](https://img.shields.io/badge/Doppler-SecretOps-purple.svg)](https://doppler.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **A SOTA (State of the Art) Zero-Leak Secret Management Skill for AI Agents.**

This repository provides the official `skill-doppler-manager` for Gemini CLI and other AI agents. It completely abolishes the traditional "fetch to local `.env`" workflow, enforcing a memory-only secret injection architecture based on **Doppler**.

By installing this skill, your AI agents will learn to:
1. 🛑 **Never leak, print, or commit raw secrets.**
2. 🏛️ **Respect the 9-Grid (Blast Radius) Isolation Architecture.**
3. 🔐 **Require Human-in-the-Loop JITA (Just-in-Time Access) for cross-domain credentials.**

---

## 📖 What's Inside?

- `SKILL.md`: The core neural instructions and operational mandates for the AI agent.
- `spec.md`: The declarative architectural specification and design philosophy.
- `references/SOP.md`: The human-centric Standard Operating Procedure for bootstrapping Doppler.
- `scripts/check_status.sh`: A lightweight, LLM-friendly status check script.

## 🚀 Installation

This skill is designed to be installed directly into your Gemini CLI environment.

```bash
# 1. Clone this repository
git clone https://github.com/plasmayang/skill-doppler-manager.git

# 2. Package the skill (Requires Gemini CLI bundled skill-creator)
# If you don't have the packager, you can directly link the folder
gemini skills install ./skill-doppler-manager --scope workspace

# 3. Reload Gemini CLI
/skills reload
```

## 🏛️ The 9-Grid Architecture

To prevent a compromised or hallucinating AI from accessing all your secrets, this skill enforces a strict 9-Grid logical isolation. The AI default scope is **ONLY** `keys4_token-providers`. For any other scope, the AI must explicitly ask for your permission (JITA).

1. `keys4_network-core` (Tailscale, Cloudflare)
2. `keys4_network-nodes` (SSH Keys)
3. `keys4_backup-core` (S3, B2)
4. `keys4_private-services` (Database, Redis)
5. `keys4_identity-providers` (OAuth, Auth0)
6. `keys4_token-providers` **(AI API Keys - Default Agent Scope)**
7. `keys4_observability-telemetry` (Grafana, Datadog)
8. `keys4_notification-channels` (Webhooks, Telegram)
9. `keys4_delivery-pipelines` (Docker, NPM)

*(See `spec.md` for deep architectural details).*

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request to improve the SOPs or AI instructions. When updating `SKILL.md`, remember the **Progressive Disclosure** principle: keep the main prompt lean and delegate long lists to the `references/` directory.

## 📜 License

MIT License. See [LICENSE](LICENSE) for details.
