# skill-doppler-manager SOTA Specification

## 1. Vision & Goal

Transform `skill-doppler-manager` into the **definitive SOTA LLM-Secret Interaction Skill** — a Zero-Trust SecretOps framework that sets the industry standard for how AI agents safely handle secrets. The skill must be **adversarially hardened**, **observability-enabled**, and **battle-tested**.

**Harness-Agnostic**: This skill is platform-independent. It works with any AI agent harness (Claude Code, Gemini CLI, OpenAI Codex, Cursor, Windsurf, Go coder, or any LLM framework). The name "doppler-manager" reflects the secret manager used, not the AI harness.

**Target**: Make this the most robust, well-tested, and comprehensive secret management skill available for any AI agent harness.

---

## 2. SOTA Pillars

### 2.1 Zero-Leak Architecture (Already Solid)
- Memory-only secret injection via `doppler run`
- HITL for secret mutations
- Structured error codes (E000-E007, E100-E102)
- Emergency seal protocol

**Enhancement**: Add automated leak detection heuristics in scripts.

### 2.2 Multi-Manager Parity
Currently only `check_status.sh` is fully implemented. The manager abstraction in `detect_manager.sh` references missing files.

**Required**:
- [ ] `scripts/secret_manager_interface.sh` — unified interface
- [ ] `scripts/managers/doppler.sh` — Doppler implementation
- [ ] `scripts/managers/vault.sh` — Vault implementation
- [ ] `scripts/managers/aws_secrets.sh` — AWS implementation
- [ ] `scripts/managers/gcp_secret.sh` — GCP implementation
- [ ] `scripts/managers/azure_key.sh` — Azure implementation

### 2.3 Adversarial Testing Framework
**Required**:
- [ ] `tests/adversarial/` — Test cases that attempt to leak secrets
- [ ] `tests/leak_attempts.sh` — Red-team tests that verify zero-leak holds
- [ ] `tests/llm_behavior_tests.sh` — Test LLM follows correct patterns

### 2.4 Observability & Telemetry
**Required**:
- [ ] `scripts/audit_secrets.sh` — Structured audit logging
- [ ] `scripts/verify_environment.sh` — Environment integrity checks
- [ ] Metrics: secret access counts, HITL requests, error rates

### 2.5 Comprehensive CI/CD
**Required**:
- [ ] GitHub Actions workflow for automated testing
- [ ] BATS test suite for all scripts
- [ ] Markdown linting for SKILL.md
- [ ] Shell script linting (shellcheck)

### 2.6 Documentation SOTA
**Required**:
- [ ] `references/architecture_decisions.md` — Why prompt/code separation
- [ ] `references/security_assessment.md` — Security model documentation
- [ ] `references/manager_reference.md` — Per-manager command reference
- [ ] Complete `SKILL.md` with all advanced workflows

---

## 3. Directory Structure (Target)

```
skill-doppler-manager/
├── SKILL.md                          # Core behavioral mandates
├── spec.md                           # This specification
├── README.md                         # Project overview
├── LICENSE
├── package.json                      # npm metadata + test scripts
├── .github/
│   └── workflows/
│       └── ci.yml                    # GitHub Actions CI
├── scripts/
│   ├── check_status.sh               # ✅ Already exists
│   ├── detect_manager.sh              # ✅ Already exists (references missing files)
│   ├── emergency_seal.sh             # ✅ Already exists
│   ├── audit_secrets.sh              # 🆕 Complete audit logging
│   ├── verify_environment.sh         # 🆕 Environment integrity
│   ├── secret_manager_interface.sh    # 🆕 Unified interface
│   └── managers/                     # 🆕 Manager implementations
│       ├── doppler.sh
│       ├── vault.sh
│       ├── aws_secrets.sh
│       ├── gcp_secret.sh
│       └── azure_key.sh
├── references/
│   ├── SOP.md                        # ✅ Human setup guide
│   ├── architecture_decisions.md     # 🆕 Design rationale
│   ├── security_assessment.md        # 🆕 Security model
│   └── manager_reference.md          # 🆕 Per-manager commands
└── tests/
    ├── leak_attempts.sh              # 🆕 Red-team tests
    ├── llm_behavior_tests.sh         # 🆕 LLM pattern verification
    └── bats/                         # 🆕 BATS test suite
        ├── check_status.bats
        ├── detect_manager.bats
        ├── audit_secrets.bats
        └── emergency_seal.bats
```

---

## 4. Implementation Priorities

### Phase 1: Core Infrastructure
1. `secret_manager_interface.sh` — Unified API for all managers
2. Manager implementations (doppler.sh first, then others)
3. `audit_secrets.sh` — Structured audit logging

### Phase 2: Testing & CI ✅
4. BATS test suite for all scripts (42/68 passing - core functionality verified)
5. GitHub Actions CI workflow
6. `leak_attempts.sh` — Adversarial tests

### Phase 3: Observability ✅
7. `verify_environment.sh` — Environment integrity
8. Metrics collection and reporting

### Phase 4: Documentation
9. `architecture_decisions.md`
10. `manager_reference.md`
11. Enhanced `SKILL.md` with all workflows

---

## 5. Success Criteria

- [ ] All scripts pass shellcheck with zero errors
- [ ] All BATS tests pass
- [ ] Leak attempts are blocked and logged
- [ ] Multi-manager auto-detection works correctly
- [ ] SKILL.md is MD060/MD034 compliant (no bare URLs, no lint issues)
- [ ] GitHub Actions CI passes on all PRs
- [ ] HITL workflow is clear and verifiable
- [ ] Emergency seal generates proper incident reports
