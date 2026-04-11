#!/bin/bash

# Integration Test: Authentication Status Check
# Verifies check_status.sh correctly reports authentication state

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing authentication status check..."

create_mock_doppler

output=$(bash "$SCRIPT_DIR/scripts/check_status.sh" 2>&1 || true)

# Parse JSON output
status=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || echo "")

if [[ "$status" == "OK" ]] || [[ "$status" == "WARNING" ]]; then
    echo "PASS: Authentication status is valid: $status"
    exit 0
else
    echo "FAIL: Unexpected status: $status"
    echo "$output"
    exit 1
fi
