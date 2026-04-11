#!/bin/bash

# Integration Test: Verify No .env File Created
# Ensures secrets are not written to disk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing that no .env file is created..."

create_mock_doppler

# Run a command that would typically need secrets
doppler run -- env > /dev/null 2>&1 || true

# Check for .env files in tmp dir
env_files=$(find "$TEST_TMP_DIR" -name ".env" -type f 2>/dev/null || true)

if [[ -n "$env_files" ]]; then
    echo "FAIL: .env file(s) were created: $env_files"
    exit 1
fi

echo "PASS: No .env file created during injection"
exit 0
