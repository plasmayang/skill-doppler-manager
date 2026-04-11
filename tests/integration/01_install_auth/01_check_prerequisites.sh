#!/bin/bash

# Integration Test: Check Prerequisites
# Verifies that basic tools are available

set -euo pipefail

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing prerequisites..."

# Test bash version
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "FAIL: Bash not detected"
    exit 1
fi

# Test required commands
for cmd in bash grep sed; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "FAIL: Required command '$cmd' not found"
        exit 1
    fi
done

echo "PASS: Prerequisites check"
exit 0
