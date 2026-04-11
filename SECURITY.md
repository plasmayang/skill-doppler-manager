# Security Policy

## Supported Versions

| Version | Supported          | Notes |
|---------|-------------------|-------|
| 1.x.x   | :white_check_mark: | Current stable |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please report it responsibly.

### Responsible Disclosure Process

1. **DO NOT** create a public GitHub issue for security vulnerabilities
2. Send a detailed report to the maintainer via email or private message
3. Include the following in your report:
   - Type of vulnerability
   - Full paths of source file(s) related to the vulnerability
   - Location of the affected source code (tag/branch/commit)
   - Step-by-step instructions to reproduce the issue
   - Proof-of-concept or exploit code (if possible)
   - Impact assessment (how could this vulnerability be exploited)

### What to Expect

- **Acknowledgment**: Within 48 hours, you will receive acknowledgment of your report
- **Initial Assessment**: We will conduct an initial assessment within 7 days
- **Resolution**: We will work on a fix and release timeline
- **Disclosure**: We will credit reporters (if desired) in the security advisory

### Scope

The following are within scope for security reports:

- Secret leakage via stdout, stderr, logs, or disk writes
- Command injection vulnerabilities
- Privilege escalation via misconfigured permissions
- Authentication bypass or token theft vectors
- Prompt injection attacks targeting the SKILL.md behavior

### Out of Scope

- Denial of Service attacks on external services
- Social engineering attacks
- Physical security issues
- Vulnerabilities in third-party secret managers (report to respective vendors)

## Security Model

### Zero-Leak Architecture

`skill-doppler-manager` enforces a **zero-leak architecture** where:

1. **Memory-only injection**: Secrets are injected into processes via secret managers (Doppler, Vault, etc.) and never touch the context window, disk, or shell history
2. **Human-in-the-Loop (HITL)**: AI agents cannot autonomously create, modify, or delete secrets
3. **Structured error codes**: All errors are encoded to prevent accidental secret exposure in error messages

### Security Properties

| Property | Enforcement |
|----------|-------------|
| No secret printing | `leak_attempt_detection()` in all scripts |
| No secret persistence | No file writes with secret values |
| No shell history | Secrets never enter bash history |
| Audit trail | All secret access logged via `audit_secrets.sh` |
| Error sanitization | Error messages never contain secret values |

## Security Best Practices for Users

1. **Use Service Tokens** for CI/CD environments (not User Tokens)
2. **Enable audit logging** in your secret manager dashboard
3. **Rotate credentials** regularly
4. **Use principle of least privilege** for access tokens
5. **Verify environment** before running: `scripts/check_status.sh`

## Security Updates

Security updates will be released as patch versions (`v1.x.x`) with priority. Subscribe to GitHub notifications to stay informed.
