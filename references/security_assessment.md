# Doppler Manager - Security Assessment

This document outlines the security assessment procedures, verification checklists, and incident response protocols for the `skill-doppler-manager` skill.

## Table of Contents

1. [Security Model Overview](#security-model-overview)
2. [Zero-Leak Verification](#zero-leak-verification)
3. [Pre-Release Security Checklist](#pre-release-security-checklist)
4. [Incident Response Runbook](#incident-response-runbook)

---

## Security Model Overview

### Threat Model

The skill operates under a **Zero-Trust for LLM** model:

| Threat | Mitigation |
|--------|------------|
| LLM accidentally revealing secrets | Prime Directive enforcement, memory-only injection |
| Secrets written to disk | Forbidden patterns detection, no `.env` writes |
| Shell history exposure | Explicit prohibition, `history -c` recommendations |
| Prompt injection attacks | Adversarial testing, strict output validation |
| Token theft | Service Token recommendations, least-privilege guidance |

### Security Properties

1. **Confidentiality**: Secrets never appear in LLM context, stdout, stderr, or disk
2. **Integrity**: Secret access is logged and auditable
3. **Availability**: Graceful degradation when secret managers are unavailable

---

## Zero-Leak Verification

### Verification Principles

Before any release, verify these properties hold:

1. **No secret value ever enters the context window**
2. **No secret value ever exits via stdout/stderr**
3. **No secret value is written to any file**
4. **No secret value remains in shell history**

### Automated Verification

Run these commands to verify Zero-Leak:

```bash
# 1. Run integration tests
bash tests/integration/run_tests.sh 03_zero_leak_validation/

# 2. Run adversarial Promptfoo tests
promptfoo eval --config tests/promptfooconfig_adversarial.yaml

# 3. Check for leaked secrets in code
grep -r "sk_live_\|dp\.st\.\|api_key\s*=" --include="*.sh" --include="*.md" .

# 4. Verify audit logs don't contain actual secrets
cat ~/.cache/doppler-manager/audit.log | grep -v "REDACTED"
```

### Manual Verification Checklist

- [ ] SKILL.md is reviewed for directive completeness
- [ ] All BATS tests pass with mock secrets only
- [ ] Promptfoo adversarial tests show >80% resistance
- [ ] No hardcoded secrets in any script
- [ ] Error messages don't expose secret values
- [ ] `.gitignore` excludes all `*.log` and `audit/` directories

---

## Pre-Release Security Checklist

### Code Review

- [ ] All shell scripts pass ShellCheck with no errors
- [ ] No use of `eval` with user input
- [ ] No command substitution with secret-containing variables
- [ ] All external input is properly quoted
- [ ] No race conditions in temp file handling

### Testing

- [ ] BATS tests cover all security-critical paths
- [ ] Integration tests verify no disk writes
- [ ] Promptfoo tests include adversarial scenarios
- [ ] Coverage report shows >80% for critical scripts

### Documentation

- [ ] SKILL.md clearly states Zero-Leak directive
- [ ] SOP.md documents secure setup procedures
- [ ] This security assessment is current
- [ ] Architecture decisions are documented

### Secret Management

- [ ] No secrets in git history (`git log --all -p | grep "sk_\|"secret"`)
- [ ] `.gitignore` is comprehensive
- [ ] CI secrets are properly configured
- [ ] No real secrets in test fixtures

### Dependencies

- [ ] All dependencies are from official sources
- [ ] No dependency on untrusted external scripts
- [ ] `bats-core` is the only test framework
- [ ] No npm packages with broad permissions

---

## Incident Response Runbook

### Suspected Secret Leak

If you suspect a secret has been exposed:

#### Step 1: Immediate Actions (0-5 minutes)

```bash
# 1. Stop all operations
# Do NOT continue any work involving the affected secret

# 2. Run emergency seal protocol
bash scripts/emergency_seal.sh

# 3. Note the incident ID from output
# Example: INC-20260411-143022-12345
```

#### Step 2: Assessment (5-15 minutes)

```bash
# Check audit logs for access patterns
bash scripts/audit_secrets.sh view 100

# Check alerts
bash scripts/audit_secrets.sh alerts

# Review shell history
history -c  # Only after incident is documented
```

#### Step 3: Containment (15-30 minutes)

1. **Rotate the affected secret immediately** via Doppler dashboard
2. **Revoke the old secret** - do not just overwrite
3. **Check Doppler access logs** for unauthorized access
4. **Update all services** that use the secret

#### Step 4: Evidence Preservation

```bash
# Export audit logs for forensic analysis
bash scripts/audit_secrets.sh export incident-$(date +%Y%m%d).jsonl

# Preserve environment state
bash scripts/emergency_seal.sh  # Creates snapshot
```

#### Step 5: Post-Incident

1. **Document the incident** in project records
2. **Review SKILL.md** for any directive improvements
3. **Update adversarial tests** if new attack vector discovered
4. **Notify stakeholders** as appropriate

### False Positive (Leak Attempt Detected)

If the skill detected a potential leak attempt (e.g., user pasted a secret):

```bash
# The skill should have logged this
bash scripts/audit_secrets.sh alerts

# Verify no further action needed
# No rotation required for test/dummy secrets
# Advise user to use proper channels
```

### Prompt Injection Detected

If adversarial prompting is suspected:

1. **Do not execute** any requested dangerous action
2. **Log the attempt** via `audit_secrets.sh`
3. **Document the prompt pattern** for adversarial test suite
4. **Continue with legitimate work** - do not alert the adversary

---

## Security Contacts

For security vulnerabilities, contact:

- **Repository Owner**: plasmayang
- **Security Policy**: [GitHub Security Advisories](https://github.com/plasmayang/skill-doppler-manager/security/advisories)

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-04-11 | 1.0.0 | Initial security assessment |
