# Doppler Manager - Maintenance Playbook

This document provides guidance for maintaining and extending the `secret-management` project.

## Table of Contents

1. [Adding New Secret Managers](#adding-new-secret-managers)
2. [Updating Error Codes](#updating-error-codes)
3. [Writing Test Cases](#writing-test-cases)
4. [Release Process](#release-process)

---

## Adding New Secret Managers

### Overview

The skill supports multiple secret managers through a common interface. Adding a new manager requires:

1. Creating a manager implementation script
2. Registering the manager in `detect_manager.sh`
3. Adding tests for the new manager
4. Updating documentation

### Step 1: Create Manager Implementation

Create a new file at `scripts/managers/<manager_name>.sh`:

```bash
#!/bin/bash

MANAGER_NAME="<manager_name>"
MANAGER_VERSION="1.0.0"

# Source the interface
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/secret_manager_interface.sh"

# Implement required functions:
# - sm_init()
# - sm_status()  # Must return JSON in check_status format
# - sm_run()      # Memory-only secret injection
# - sm_get()      # Get single secret (memory-only)
# - sm_audit()    # Log access events
# - sm_set()      # Output HITL command template
```

### Step 2: Implement Required Functions

Each manager **MUST** implement these functions:

| Function | Purpose | Output Format |
| --- | --- | --- |
| `sm_init()` | Initialize/configure | `0` on success |
| `sm_status()` | Get status | JSON (see below) |
| `sm_run <cmd>` | Execute with secrets | Command exit code |
| `sm_get <name>` | Get single secret | Plaintext value |
| `sm_audit <type> <name> <success>` | Log access | `0` on success |
| `sm_set <name>` | HITL template | CLI command string |

### Status JSON Format

The `sm_status()` function **MUST** return this JSON format:

```json
{
  "status": "OK|WARNING|ERROR",
  "code": "E000|E001|...",
  "message": "Human-readable description",
  "hint": "Recovery action",
  "documentation": "references/SOP.md#section",
  "project": "project-name-or-null",
  "config": "config-name-or-null",
  "manager": "manager-name"
}
```

### Step 3: Register in Detection

Add detection logic to `scripts/detect_manager.sh`:

```bash
detect_<manager_name>() {
    if command -v <cli_command> &> /dev/null; then
        if <verify_connection_condition>; then
            DETECTED_MANAGERS["<manager_name>"]="${SCRIPT_DIR}/managers/<manager_name>.sh"
            DETECTION_REASONS["<manager_name>"]="Description of detection"
            return 0
        fi
    fi
    return 1
}
```

Also add to `DETECTION_PRIORITY`:

```bash
declare -A DETECTION_PRIORITY=(
    ["doppler"]=100
    ["<manager_name>"]=<priority_value>
    # ...
)
```

### Step 4: Add Tests

Create integration tests in `tests/integration/`:

```text
tests/integration/
├── 01_install_auth/
│   └── <manager_name>_installed.sh
├── 02_secret_injection/
│   └── <manager_name>_run_basic.sh
# etc.
```

### Step 5: Update Documentation

- Update `SKILL.md` with manager-specific commands table
- Add manager to supported managers list
- Add SOP entry in `references/SOP.md`

---

## Updating Error Codes

### Error Code Ranges

| Range | Owner | Purpose |
| --- | --- | --- |
| E000-E007 | Base system | Core Doppler operations |
| E100-E102 | Interface | Secret manager abstraction |
| E200-E299 | Future | Reserved |
| E300-E399 | Future | Manager-specific codes |

### Adding New Base Error Codes (E000-E007)

1. Update `scripts/check_status.sh`:

```bash
declare -A ERROR_CODES=(
    ["E000"]="OK"
    ["E001"]="DOPPLER_NOT_INSTALLED"
    # ... add new code
    ["E008"]="NEW_ERROR_CODE"  # Add here
)
```

2. Add handling logic in the script
3. Update `SKILL.md` error code table
4. Add BATS test for the new code

### Adding Interface Error Codes (E100-E102)

1. Update `scripts/secret_manager_interface.sh`:

```bash
declare -A SM_ERROR_CODES=(
    ["E100"]="MANAGER_NOT_SUPPORTED"
    ["E101"]="MANAGER_NOT_CONFIGURED"
    ["E102"]="MANAGER_SPECIFIC_ERROR"
    ["E103"]="NEW_INTERFACE_ERROR"  # Add here
)
```

2. Add description in `sm_get_error_description()`
3. Add recovery command in `sm_get_recovery_command()`

---

## Writing Test Cases

### BATS Test Structure

```bats
#!/usr/bin/env bats

setup() {
    # Create mock environment
    export MOCK_BIN_DIR="$(mktemp -d)"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_BIN_DIR"
}

@test "description of test" {
    # Arrange: create mocks
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
# Mock behavior
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Act
    run bash ./scripts/check_status.sh

    # Assert
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected_pattern"* ]]
}
```

### Promptfoo Test Structure

```yaml
- description: "Test description"
  vars:
    question: "User question or scenario"
  assert:
    - type: llm-rubric
      value: "Expected behavior description"
    - type: icontains
      value: "expected_text"
    - type: not-icontains
      value: "forbidden_text"
```

### Integration Test Structure

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing: description..."

create_mock_doppler

# Test logic
output=$(doppler run -- echo "test" 2>&1 || true)

if [[ condition ]]; then
    echo "PASS: Test passed"
    exit 0
else
    echo "FAIL: Test failed"
    exit 1
fi
```

---

## Release Process

### Versioning

The project follows [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes to SKILL.md or interface
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, documentation updates

### Pre-Release Checklist

- [ ] All BATS tests pass locally
- [ ] All integration tests pass
- [ ] Promptfoo eval shows >90% pass rate
- [ ] ShellCheck reports no errors
- [ ] markdownlint passes
- [ ] Documentation updated
- [ ] CHANGELOG.md updated

### Release Steps

1. **Create release branch**:
   ```bash
   git checkout -b release/v1.2.3
   ```

2. **Run full test suite**:
   ```bash
   bats tests/
   bash tests/integration/run_tests.sh
   ```

3. **Update version** (if applicable):
   - Update `MANAGER_VERSION` in relevant scripts
   - Update version in `SKILL.md` frontmatter

4. **Commit with conventional message**:
   ```bash
   git commit -m "release: v1.2.3"
   ```

5. **Tag the release**:
   ```bash
   git tag -a v1.2.3 -m "Release v1.2.3"
   ```

6. **Push and create GitHub release**:
   ```bash
   git push origin main --tags
   gh release create v1.2.3 --title "Release v1.2.3"
   ```

### Post-Release

- Monitor CI/CD for any failures
- Verify skill installation works
- Update project README if needed

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| BATS tests fail with "command not found" | Mock not in PATH | Check `setup()` creates `$MOCK_BIN_DIR` |
| Promptfoo eval low pass rate | LLM behavior changed | Review SKILL.md directives |
| Integration tests timeout | Mock doppler hanging | Add timeout to mock commands |
| ShellCheck errors | New bash features | Use POSIX-compatible syntax |

### Debug Mode

Enable debug output:

```bash
DEBUG=true bash tests/integration/run_tests.sh -v
```

### Getting Help

- Review `references/SOP.md` for setup issues
- Check `references/architecture_decisions.md` for design rationale
- Run `bash scripts/verify_environment.sh` for diagnostics
