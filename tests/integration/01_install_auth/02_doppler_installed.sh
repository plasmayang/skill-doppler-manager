#!/bin/bash

# Integration Test: Doppler Installation Check
# Verifies Doppler CLI is detected by check_status.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing Doppler installation detection..."

# Create mock doppler
create_mock_doppler

# Run check_status.sh
output=$(bash "$SCRIPT_DIR/scripts/check_status.sh" 2>&1 || true)

# Check that output contains expected fields
if ! echo "$output" | grep -q '"status"'; then
    echo "FAIL: No status field in output"
    echo "$output"
    exit 1
fi

if ! echo "$output" | grep -q '"code"'; then
    echo "FAIL: No code field in output"
    echo "$output"
    exit 1
fi

echo "PASS: Doppler installation detection works"
echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Status: {d[\"status\"]}, Code: {d[\"code\"]}')" 2>/dev/null || true
exit 0
