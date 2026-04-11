# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-04-11

### Added

- **SOTA SKILL.md** with Zero-Leak Directive, HITL enforcement, and 9 advanced workflows
- **leak_attempt_detection()** heuristics in all scripts for adversarial hardening
- **Structured JSON status** via `check_status.sh` with E000-E007, E100-E102 error codes
- **Multi-manager auto-detection** via `detect_manager.sh` with priority ranking
- **Secret masking** in all JSON output, error messages, and audit logs
- **Adversarial prompt resistance** via promptfooconfig.yaml behavioral tests
- **Secret expiry/rotation detection** with proactive warnings
- **HITL template commands** for all secret mutations (no direct `set` commands)
- **Environment hygiene checks** via `verify_environment.sh`

### Security

- Zero-leak architecture verified via 10+ leak_attempt tests
- Shell history sanitization verification
- JSON output sanitization across all scripts
- Emergency seal protocol with incident reporting

## [1.1.0] - 2026-04-10

### Added

- **Multi-manager support**: Doppler, Vault, AWS, GCP, Azure, Infisical
- **Manager implementations**: `managers/doppler.sh`, `vault.sh`, `aws_secrets.sh`, `gcp_secret.sh`, `azure_key.sh`
- **Unified interface**: `secret_manager_interface.sh` with `sm_status`, `sm_run`, `sm_get`, `sm_set`
- **Manager reference documentation**: `references/manager_reference.md`
- **Per-manager priority system**: Auto-selection of best available manager

### Changed

- `detect_manager.sh` now references all manager implementations
- Structured output format standardized across all scripts

## [1.0.0] - 2026-04-09

### Added

- **Initial release** of skill-doppler-manager
- **Doppler CLI integration** as primary secret manager
- **BATS test suite** with 78 tests covering all core scripts
- **GitHub Actions CI/CD** with ShellCheck, markdownlint, BATS, and Promptfoo
- **Comprehensive documentation**: SKILL.md, references/SOP.md, references/architecture_decisions.md
- **Emergency response protocol** via `emergency_seal.sh`
- **Audit logging** via `audit_secrets.sh` (JSONL format)
- **Error code system** for structured failure diagnosis

[1.2.0]: https://github.com/plasmayang/skill-doppler-manager/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/plasmayang/skill-doppler-manager/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/plasmayang/skill-doppler-manager/releases/tag/v1.0.0
