# Contributing to secret-management

Thank you for your interest in contributing to secret-management, the Zero-Trust SecretOps framework for AI agents.

## Code of Conduct

This project adheres to a strict **zero-leak security model**. All contributors must respect the following principles:

- **Never** introduce code that could expose secrets to stdout, stderr, logs, or disk
- **Never** add hardcoded credentials or secret values
- **Always** use environment variables or secret manager interfaces for secrets
- **Always** run `bats tests/` and `shellcheck` before submitting PRs

## Commit Convention

We use **Conventional Commits** for clear and structured commit history:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, whitespace (no code change) |
| `refactor` | Code restructuring (no feature/fix) |
| `test` | Adding or updating tests |
| `chore` | Maintenance, dependencies |
| `perf` | Performance improvement |
| `ci` | CI/CD changes |
| `security` | Security-related change |

### Examples

```bash
git commit -m "feat(doppler): add service token detection"
git commit -m "fix: resolve verify_environment.bats mock failures"
git commit -m "docs(SKILL.md): add multi-manager advanced workflows"
git commit -m "security: add leak_attempt_detection heuristics"
git commit -m "ci: add shellcheck to lint pipeline"
```

## Development Setup

### Prerequisites

- Bash 4.0+
- [BATS](https://github.com/bats-core/bats-core) (`brew install bats-core`)
- [ShellCheck](https://www.shellcheck.net/) (`brew install shellcheck`)
- Doppler CLI, Vault CLI, or other supported secret managers (optional, for integration testing)

### Local Development Workflow

```bash
# 1. Clone the repository
git clone https://github.com/plasmayang/secret-management.git
cd secret-management

# 2. Install dependencies
npm install

# 3. Run the test suite
bats tests/

# 4. Run shellcheck on all scripts
shellcheck scripts/**/*.sh

# 5. Run markdown lint
npm run lint:md
```

## Pull Request Process

### PR Requirements

All PRs must satisfy:

- [ ] All BATS tests pass (`bats tests/`)
- [ ] ShellCheck reports zero errors
- [ ] Markdown lint passes
- [ ] No hardcoded secrets or credentials
- [ ] New scripts have corresponding BATS tests
- [ ] Commit messages follow Conventional Commits

### PR Structure

1. **Fork** the repository
2. **Create a feature branch**: `git checkout -b feat/my-feature`
3. **Make your changes** following the coding standards
4. **Test thoroughly**: `bats tests/ && shellcheck scripts/**/*.sh`
5. **Commit** using Conventional Commits
6. **Push**: `git push origin feat/my-feature`
7. **Open a PR** against `main`

### PR Title Format

```
<type>(<scope>): <short description>

[optional detailed description]

Closes #<issue-number>
```

## Security Contributions

If you discover a security vulnerability:

1. **DO NOT** open a public GitHub issue
2. Email the maintainer directly at the address in SECURITY.md
3. Wait for acknowledgment before disclosing details
4. Follow responsible disclosure practices

## Releasing

Releases are managed by the maintainer using semantic versioning:

1. Update `CHANGELOG.md` with all changes since last release
2. Create a git tag: `git tag -a v1.x.x -m "Release v1.x.x"`
3. Push tag: `git push origin v1.x.x`
4. GitHub Actions will automatically publish

## Getting Help

- **Issues**: Open at https://github.com/plasmayang/secret-management/issues
- **Discussions**: Use GitHub Discussions
- **Security**: See SECURITY.md
