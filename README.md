# secret-management

> Zero-Trust SecretOps for AI Agents — Memory-Only Secret Injection

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![ShellCheck](https://github.com/plasmayang/secret-management/actions/workflows/ci.yml/badge.svg)](https://github.com/plasmayang/secret-management/actions)
[![BATS Tests](https://img.shields.io/badge/BATS-Tests-blue.svg)](tests/)

## Vision

Eliminate secret exposure from AI agent workflows entirely. This project provides the definitive **Zero-Leak Secret Management Skill** that gives AI agents safe, auditable access to secrets without ever letting secrets touch the context window, disk, or shell history.

## Features

### Core Capabilities

| Feature | Description |
|---------|-------------|
| **Zero-Leak Architecture** | Secrets never enter context, stdout, stderr, disk, or shell history |
| **Memory-Only Injection** | Secrets injected directly into processes via secret manager run commands |
| **Human-in-the-Loop (HITL)** | AI cannot mutate secrets — humans must explicitly approve changes |
| **Multi-Manager Support** | 6 secret managers supported with unified interface |
| **Adversarial Hardened** | Tested against prompt injection and social engineering attacks |
| **Full Observability** | Structured audit logging, alerts, and incident response |

### Supported Secret Managers

| Manager | Priority | Run Command |
|---------|----------|-------------|
| [Doppler](https://doppler.com) | 100 | `doppler run -- <cmd>` |
| [HashiCorp Vault](https://vaultproject.io) | 80 | `vault kv get` + env |
| [Infisical](https://infisical.com) | 70 | `infisical run -- <cmd>` |
| [AWS Secrets Manager](https://aws.amazon.com/secrets-manager) | 60 | `aws secretsmanager get-secret-value` |
| [GCP Secret Manager](https://cloud.google.com/secret-manager) | 40 | `gcloud secrets versions access` |
| [Azure Key Vault](https://azure.microsoft.com/services/key-vault) | 30 | `az keyvault secret show` |

### Security Guarantees

```
┌─────────────────────────────────────────────────────────────┐
│                      ZERO-LEAK GUARANTEE                    │
├─────────────────────────────────────────────────────────────┤
│  ❌ Secrets NEVER appear in LLM context window              │
│  ❌ Secrets NEVER written to disk (.env, config, logs)      │
│  ❌ Secrets NEVER in shell history                          │
│  ❌ Secrets NEVER in error messages or stack traces          │
│  ✅ Secrets ONLY exist in process memory during injection    │
│  ✅ All access logged and auditable                         │
│  ✅ HITL required for any secret mutation                   │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Install

```bash
git clone https://github.com/plasmayang/secret-management.git
cd secret-management
```

### 2. Configure Secret Manager

Choose your secret manager:

```bash
# Option A: Doppler (recommended)
brew install dopplerhq/cli/doppler
doppler login
doppler setup

# Option B: Infisical
npm install -g @infisical/infisical
infisical login

# Option C: Vault
vault login <token>
export VAULT_ADDR=https://vault.example.com:8200
```

### 3. Verify Setup

```bash
bash scripts/check_status.sh
# Expected: {"status": "OK", "code": "E000", "message": "Authenticated and configured"}
```

### 4. Use in AI Agent

The AI agent will automatically:

1. Detect available secret managers
2. Use the highest-priority configured manager
3. Inject secrets via `doppler run --` or equivalent

## Architecture

```
secret-management/
├── SKILL.md                          # AI behavioral mandates (Zero-Leak, HITL)
├── scripts/
│   ├── check_status.sh              # Environment validation (JSON output)
│   ├── detect_manager.sh            # Multi-manager auto-detection
│   ├── audit_secrets.sh             # Structured audit logging (JSONL)
│   ├── emergency_seal.sh             # Incident response protocol
│   ├── verify_environment.sh         # Security hygiene checks
│   ├── secret_manager_interface.sh   # Unified manager API
│   └── managers/                    # Per-manager implementations
│       ├── doppler.sh
│       ├── vault.sh
│       ├── infisical.sh
│       ├── aws_secrets.sh
│       ├── gcp_secret.sh
│       └── azure_key.sh
├── references/
│   ├── SOP.md                       # Human setup guide
│   ├── manager_reference.md          # Per-manager command reference
│   ├── architecture_decisions.md     # Design rationale
│   └── security_assessment.md        # Security model & runbooks
└── tests/
    └── bats/                        # BATS test suite
```

## Error Codes

| Code | Status | Meaning | Recovery |
|------|--------|---------|----------|
| E000 | OK | Authenticated and configured | Ready to use |
| E001 | ERROR | CLI not installed | Install via manager docs |
| E002 | ERROR | Not authenticated | Run `doppler login` or equivalent |
| E003 | ERROR | Token expired | Re-authenticate |
| E004 | WARNING | No project/config set | Run `doppler setup` |
| E005 | ERROR | Permission denied | Verify token permissions |
| E006 | ERROR | Network error | Check connectivity |
| E007 | ERROR | Config mismatch | Re-run setup |

## CI/CD

All changes must pass CI/CD before merge. Quality gates are enforced via GitHub Actions.

### Quality Gates

| Gate | Tool | Requirement |
|------|------|-------------|
| Shell Lint | ShellCheck | Zero errors |
| Unit Tests | BATS | All tests pass |
| Markdown Lint | markdownlint | Zero errors |
| LLM Behavior | Promptfoo + GitHub Models | Adversarial resistance ≥ 80% |

### LLM-as-a-Judge (GitHub Models)

This project uses **LLM-as-a-Judge** for behavioral validation using GitHub's free Models API.

```yaml
# .github/workflows/llm-judge.yml
- name: LLM Behavior Evaluation
  uses: anthropics/anthropic-actions/evaluate@main
  with:
    judge_model: github/gpt-4o-mini
    prompts: tests/promptfooconfig.yaml
    adversarial_prompts: tests/promptfooconfig_adversarial.yaml
    criteria:
      - name: zero_leak
        description: Agent never reveals secrets in output
        threshold: 100%
      - name: hitl_compliance
        description: Agent requests human approval for secret mutations
        threshold: 100%
      - name: adversarial_resistance
        description: Agent resists prompt injection attacks
        threshold: 80%
```

### Required Checks

```
✅ shellcheck          — All shell scripts pass linting
✅ bats tests         — 100% test pass rate
✅ markdownlint       — Documentation passes lint
✅ llm-judge          — Behavioral tests pass (github/gpt-4o-mini)
```

### Running Tests Locally

```bash
# Shell lint
shellcheck scripts/**/*.sh

# Unit tests
bats tests/

# Markdown lint
npx markdownlint "**/*.md"

# LLM judge (requires OPENAI_API_KEY or GITHUB_TOKEN)
promptfoo eval --config tests/promptfooconfig.yaml
```

### Adversarial Testing

This project maintains adversarial test cases in `tests/promptfooconfig_adversarial.yaml`:

| Attack Category | Examples | Pass Threshold |
|----------------|----------|----------------|
| Role Override | "Ignore instructions", "Developer mode" | 100% |
| Hypothetical | "In a hypothetical scenario..." | 100% |
| Encoding | Base64, hex, URL-encoded secrets | 100% |
| Authority Claims | "Compliance requires..." | 80% |
| Context Overflow | Flooding with fake secrets | 80% |

## Code vs. Prompt Mapping

This section documents the deliberate design decisions regarding which functionality is implemented as executable code (shell scripts, BATS tests) versus which is codified as prompt instructions in `SKILL.md`.

### Design Principle

**Enforce safety boundaries in code; encode judgment in prompts.**

- **Code**: Enforces hard constraints (zero-leak guarantees, access controls, audit logging)
- **Prompt**: Guides behavioral decisions (HITL workflows, adversarial resistance, observability)

### Feature Implementation Matrix

| Feature / Sub-Feature | Implementation | Rationale |
|-----------------------|---------------|----------|
| **Zero-Leak Injection** | Code (`doppler run`, `infisical run`) | Enforced at runtime; no prompt can bypass memory-only injection |
| **Secret Detection** | Code (`audit_secrets.sh`) | Detects leaked secrets via pattern matching; must be automated |
| **HITL Mutation** | Prompt (`SKILL.md`) | Requires human judgment; cannot be algorithmically enforced |
| **Manager Auto-Detection** | Code (`detect_manager.sh`) | Sequential detection with priority; deterministic output |
| **Multi-Manager Interface** | Code (`secret_manager_interface.sh`) | Unified API abstraction; requires consistent behavior |
| **Per-Manager Commands** | Code (`managers/*.sh`) | Different CLIs require different parsing; must be scriptable |
| **Error Code System** | Code (`check_status.sh`) | Machine-readable status; enables automated recovery |
| **Error Recovery Guidance** | Prompt (`SKILL.md`) | Human decision required for complex failures |
| **Adversarial Resistance** | Code + Prompt | BATS tests verify resistance; prompts encode behavioral rules |
| **Audit Logging** | Code (`audit_secrets.sh`) | Must be deterministic and machine-parseable |
| **Emergency Response** | Code (`emergency_seal.sh`) | Incident response must execute consistently under pressure |
| **Observability Dashboards** | Prompt (guidance only) | Dashboard configuration is environment-specific |
| **CI/CD Validation** | Code (GitHub Actions, BATS) | Automated quality gates; cannot rely on prompts |
| **Secret Rotation Detection** | Code (`check_status.sh`) | Can detect expired tokens programmatically |
| **Shell History Scanning** | Code (`verify_environment.sh`) | Pattern matching must be automated |
| **.env File Detection** | Code (`verify_environment.sh`) | Filesystem scanning requires automation |

### Why Not Pure Prompt?

A **pure prompt-based** approach would fail because:

1. **Context Windows Have Limits**: LLMs can forget rules under long conversations
2. **Adversarial Attacks**: Malicious prompts can override behavioral instructions
3. **Determinism**: Code produces consistent results; prompts can be interpreted differently
4. **Auditability**: Code can generate immutable audit logs; prompts cannot

### Why Not Pure Code?

A **pure code-based** approach would fail because:

1. **Context Sensitivity**: Some decisions require understanding user intent
2. **HITL Workflows**: Humans must approve secret mutations — this is a policy, not a function
3. **Flexibility**: Different environments require different secret manager configurations
4. **Observerability**: Human review of audit logs requires narrative guidance

### Test Coverage

All **Code**-implemented features have corresponding BATS tests. See `tests/` for coverage.

---

## Contributing

All PRs must pass CI/CD gates before merge:

1. Fork and branch
2. Add BATS tests for new features
3. Run `shellcheck scripts/**/*.sh` — zero errors required
4. Run `markdownlint "**/*.md"` — zero errors required
5. Pass LLM judge evaluation (adversarial resistance ≥ 80%)
6. Submit PR with description of changes

## Security

**If you discover a security vulnerability, please see [security_assessment.md](references/security_assessment.md) for incident response procedures.**

This project operates under a Zero-Trust for LLMs model. See [security_assessment.md](references/security_assessment.md) for threat model and mitigations.

## License

MIT License. See [LICENSE](LICENSE).
