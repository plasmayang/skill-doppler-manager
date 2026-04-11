#!/bin/bash

# Integration Test: HITL - Secret Set Command Template
# Verifies the skill outputs a proper command template for HITL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$SCRIPT_DIR/tests/integration/run_tests.sh" 2>/dev/null || true

echo "Testing HITL: secret set command template..."

create_mock_doppler

# Source the manager interface and get the set command template
if [[ -f "$SCRIPT_DIR/scripts/managers/doppler.sh" ]]; then
    source "$SCRIPT_DIR/scripts/managers/doppler.sh"

    # Get the set template
    output=$(sm_set "MY_TEST_SECRET" 2>&1 || true)

    if ! echo "$output" | grep -q "doppler secrets set"; then
        echo "FAIL: No doppler secrets set command in output"
        exit 1
    fi

    if echo "$output" | grep -q "MY_TEST_SECRET="; then
        echo "FAIL: Secret value appeared in command template"
        exit 1
    fi

    echo "PASS: HITL command template is correct"
    echo "$output"
    exit 0
else
    echo "SKIP: Manager implementation not found"
    exit 0
fi
