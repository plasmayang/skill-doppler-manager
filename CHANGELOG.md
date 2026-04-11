# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-04-11

### Added

- **Claude Code Skill Native Integration**: `.claude/skills/doppler-skill/manifest.json`, tool definitions, and skill.md
- **GitHub Milestones Roadmap**: `.github/milestones/roadmap.json` with v2.0-v2.2 release plan
- **git-secrets CI Integration**: `scan-secrets` job in CI workflow to catch accidental secret commits
- **Secret Lease/TTL Management**: `scripts/secret_lease.sh` with token bucket algorithm
- **Secret Rotation Automation**: `scripts/secret_rotation.sh` for stale secret detection (> 90 days)
- **Secret Access Request Workflow**: `scripts/access_request.sh` for HITL approval/rejection
- **Rate Limiting Protection**: `scripts/rate_limit.sh` for audit logging DoS prevention
- **OTLP Trace Export**: Enhanced `tracing.sh` with distributed tracing export capability
- **Integration Test Suite**: `tests/integration/` with mock infrastructure and 5 test categories
- **ADR-014 to ADR-020**: New architecture decisions for SOTA features
- **GitHub Releases Workflow**: `.github/workflows/releases.yml` for automated releases

### Security

- git-secrets scanning on every PR and push
- Rate limiting on all audit operations (sm_run: 60/min, sm_fetch: 120/min, sm_audit: 30/min)
- Secret lease tracking prevents indefinite secret holding
- Rotation detection forces periodic secret validation

### Infrastructure

- 4 new BATS tests added to core suite
- Integration tests with mock Doppler/Vault/AWS CLI
- Full OTLP export with span batching (100 spans or 5s flush)

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

- **Initial release** of secret-management
- **Doppler CLI integration** as primary secret manager
- **BATS test suite** with 78 tests covering all core scripts
- **GitHub Actions CI/CD** with ShellCheck, markdownlint, BATS, and Promptfoo
- **Comprehensive documentation**: SKILL.md, references/SOP.md, references/architecture_decisions.md
- **Emergency response protocol** via `emergency_seal.sh`
- **Audit logging** via `audit_secrets.sh` (JSONL format)
- **Error code system** for structured failure diagnosis

[1.2.0]: https://github.com/plasmayang/secret-management/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/plasmayang/secret-management/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/plasmayang/secret-management/releases/tag/v1.0.0
