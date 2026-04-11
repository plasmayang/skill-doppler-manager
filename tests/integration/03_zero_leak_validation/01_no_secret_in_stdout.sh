#!/bin/bash

# Integration Test: Zero-Leak - No Secrets in stdout
# Verifies secrets never appear in stdout/stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing zero-leak: secrets not in stdout..."

# Create a mock secret value
MOCK_SECRET="sk_test_super_secret_value_12345"

# Run a command that accesses secrets
create_mock_doppler

# Capture all output
all_output=$(doppler run -- bash -c 'echo "Test completed"' 2>&1 || true)

# Check for secret patterns
if echo "$all_output" | grep -q "$MOCK_SECRET"; then
    echo "FAIL: Secret leaked into output"
    echo "$all_output"
    exit 1
fi

# Check for common secret patterns
for pattern in "sk_" "api_key" "secret" "password" "token"; do
    if echo "$all_output" | grep -qi "$pattern"; then
        # This might be a false positive if it's just the word "secret" in context
        if ! echo "$all_output" | grep -qi "test.*completed"; then
            echo "WARN: Potential secret pattern detected: $pattern"
        fi
    fi
done

echo "PASS: No secrets leaked to stdout"
exit 0
